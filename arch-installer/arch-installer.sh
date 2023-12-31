# Remember to remove sudo from commands TODO
#
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%.....GLOBAL VARIABLES......%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

TIMEZONE=""
AUR_HELPER="https://aur.archlinux.org/yay.git"
EFI_PARTS=()
EFI_PART=""
EFI_STATUS=""
EFI_SIZES=()
EFI_SIZE=""
EFI_COUNTER=0
INSTALL_DISK=""
LINUX_PART=""
USER=""
HOSTNAME=""
REPO_DIR=""
# IMPORTANT: don't call the variable PATH as the subshell will interpret it as empty PATH
PATH_SCRIPT=""
LINK="files.yugos.xyz/scripts"

#
#
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%........FUNCTIONS........%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

# Used to exit the program
# shows the cause of crash
error() {
  printf '%s\n' "$1"
  exit 1
}

# load the keymap
loadKeymap() {
  list_keymaps=()
  local keymap_file="keymap.txt"
  localectl list-keymaps > $keymap_file
  while read -r keymap; do
    list_keymaps+=("${keymap}" "")
  done < $keymap_file
  if whiptail --title "Keymap" --yesno "Do you want to change your keymap?\nDefault: \"us\" " 0 0 3>&1 1>&2 2>&3; then
    keymap=$(whiptail --title "Keymap" --menu "Select a keymap" 0 60 0 "${list_keymaps[@]}" 3>&1 1>&2 2>&3) 
    loadkeys $keymap
  else
    echo "Keymap not set"
  fi
}

# Set the correct timezone 
setTimeZone() {
	LIST_TIMEZONES=()
	local time_file="timezones.txt"
  timedatectl set-ntp true
	timedatectl list-timezones > $time_file
	while read -r timezone; do
		LIST_TIMEZONES+=("${timezone}" "")
	done < $time_file
  TIMEZONE=$(whiptail --title "Timezone" --menu "Select a timezone" 0 60 0 "${LIST_TIMEZONES[@]}" 3>&1 1>&2 2>&3) || error "User exited"
  timedatectl set-timezone ${TIMEZONE}
	rm $time_file
}

# check for existing EFI filesystems
# works with "/dev/sdx" format 
# ---
# checkEfiFileSystem PARTITION
checkEfiFileSystem() {
  local part=$(printf "$1" | sed 's/:.*//')
  local checker=$(printf 'p' | fdisk $part | grep "EFI" | cut -d' ' -f1)
  
  if [ $(printf 'p' | fdisk "$part" | grep "EFI" >> /dev/null; printf $?) -eq 0 ]
  then
    EFI_PARTS+=("$checker")
    EFI_STATUS=0
    EFI_SIZES+=("$(printf 'p' | fdisk $part | grep "EFI" | tr -s ' ' | cut -d' ' -f5)")
    whiptail --title 'Alert' --msgbox \
    "Found an EFI partition on $part \nLocation: $checker \nSize: ${EFI_SIZES[$EFI_COUNTER]}" 10 40 3>&1 1>&2 2>&3
    printf "$part"
  else
    whiptail --title 'Alert' --msgbox \
    "No EFI partition found on $part" 10 40 3>&1 1>&2 2>&3
    EFI_STATUS=1
  fi
}

# select install disk
# takes disk list file as input
# ---
# selectInstallDisk DISK_LIST 
selectInstallDisk() {
  local part_list=()
  local counter=0
  while read -r part; do
    if echo "$part" | grep -q "sd"; then
      if [ "$(echo "$part" | sed 's/:.*//')" = "$(echo "${EFI_PARTS[$counter]}" | sed 's/[0-9]*$//')" ]; then
        part_list+=("${part}" "   (EFI)")
        counter=$((counter+1))
      else
        part_list+=("${part}" "")
      fi
    fi
    if echo "$part" | grep -q "nvm"; then
      if [ "$(echo "$part" | sed 's/:.*//')" = "$(echo "${EFI_PARTS[$counter]}" | sed 's/[a-z][0-9]*$//')" ]; then
        part_list+=("${part}" "   (EFI)")
        counter=$((counter+1))
      else
        part_list+=("${part}" "")
      fi
    fi
  done < $1
  INSTALL_DISK=$(whiptail --title "Select disk" --menu "Select an installation disk" 0 60 20 "${part_list[@]}" 3>&1 1>&2 2>&3 | sed "s/:.*//")
  #printf "g\nw" | fdisk $INSTALL_DISK
  parted --script $INSTALL_DISK mklabel gpt
  if [ $(printf "p" | fdisk $INSTALL_DISK 2>&1 | grep "EFI" 2>&1 > /dev/null; echo $?) -eq 0 ]; then
    EFI_PART="$(printf 'p' | fdisk $INSTALL_DISK 2>&1 | grep "EFI" | cut -d' ' -f1)"
    #echo $EFI_PART
  fi
}

# wipe all past signatures
# takes partition from wipeDisk as input
# -----
# wipePartitionSignature partition
# wipePartitionSignature() {
#   local partition="$1"
#   wipefs -a $partition
#   echo "Cleaned the $partition signature"
# }

wipePartition() {
  local partition="$1"
  output=$(echo "$partition" | sed 's/[^0-9]*//g')
  # printf "d\n$output\nw" | fdisk $INSTALL_DISK
  umount -l "$partition"
  yes | parted --script "$INSTALL_DISK" rm "$output"
  if [ $? -eq 0 ]; then
    echo "Partition $partition deleted succesfully"
  else
    error "Partition didn't delete"
  fi
}

# wipe disk partitions
# takes INSTALL_DISK as input
wipeDisk() {
  local partitions=()
  local output="$(printf "p" | fdisk "$1" 2>&1 | sed -n '/Device/,/^\s*$/p' | sed '$d; 1d' | tr -s ' ' | cut -d' ' -f1)"
  if [ -z "$output" ]; then
    echo "No partitions found. Skipping..."
    return 1
  fi

  if [ -n "$EFI_PART" ]; then
    if whiptail --title "Wipe disk" --yesno "Do you want to delete your EFI partition?\nAll the data will be lost" 0 0 3>&1 1>&2 2>&3; then
      while IFS= read -r line; do
        #wipePartitionSignature $line
        wipePartition $line
      done <<<  "$output"
    else
      while IFS= read -r line; do
        for partition in "${EFI_PARTS[@]}"; do
          if [ "$line" = "$partition" ];then
            EFI_PART=$partition
            echo "Skipping"
          else
            #wipePartitionSignature $line
            wipePartition $line
          fi
        done
      done <<<  "$output"
    fi
  else
    whiptail --title "Wipe disk" --msgbox "Skipping EFI wipe" 0 0 3>&1 1>&2 2>&3
    while IFS= read -r line; do
      #wipePartitionSignature $line
      wipePartition $line
    done <<<  "$output"
  fi
}

# swap
# cat /proc/meminfo | grep "MemTotal" | tr -s ' ' | cut -d' ' -f2 | awk '{printf "%d\n", $1/1024}'

# creates a partition for the EFI
createEfiPartition() {
  local number=1
  local sizes=("128M" "" "256M" "" "512M" "")
  local size=$(whiptail --title "Create EFI partition" --menu "Choose the partition size\nIf you don't plan on using more than one OS\nsize can be kept rather small" 0 0 0 "${sizes[@]}" 3>&1 1>&2 2>&3) || error "User exited"
  #printf "n\n1\n\n+$size\nw" | fdisk $INSTALL_DISK
  #printf "t\n1\nw" | fdisk $INSTALL_DISK
  parted --script $INSTALL_DISK mkpart primary fat32 1MiB "$size"iB
  parted --script $INSTALL_DISK set 1 esp on
  EFI_PART="$INSTALL_DISK$number"
  EFI_SIZE="$size"
  echo "EFI partition created succesfully"
}

# creates a FAT32 filesystem for the EFI partition
createEfiFileSystem() {
  mkfs.fat -F32 "$EFI_PART"
}

# creates a partition with Linux filesystem
createLinuxPartition() {
  local output="$(printf "p" | fdisk $INSTALL_DISK 2>&1 | sed -n '/Device/,/^\s*$/p' | sed '$d; 1d' | tr -s ' ' | cut -d' ' -f1)"
  local number=0
  while IFS= read -r line; do
    if [ "$line" = "$EFI_PART" ]; then
      number=$((number + $(echo "$line" | sed 's/[^0-9]*//g') + 1))
      #printf "n\n$number\n\n\nw" | fdisk $INSTALL_DISK
      parted --script $INSTALL_DISK mkpart primary ext4 "$EFI_SIZE"iB 100%
    else
      number=2
      #printf "n\n$number\n\n\nw" | fdisk $INSTALL_DISK
      parted --script $INSTALL_DISK mkpart primary ext4 "$EFI_SIZE"iB 100%
    fi
  done <<< "$output"
  LINUX_PART="$INSTALL_DISK$number"
  whiptail --title "Create Linux partition" --msgbox "Linux partition created" 8 40
  echo "Linux partition created succesfully"
  echo $LINUX_PART
}

# create a ext4 filesystem for Linux partition
createLinuxFileSystem() {
  mkfs.ext4 "$LINUX_PART"
}

# create an EFI and Linux partition
createDisk() {
  local part_list="fdisk-list.txt"
  whiptail --title "Create Partition" --msgbox "This tool will guide you through partition creation process. \
    \nIn the current state, it aims to create 2 partitions: \n\
      -an EFI (fat32) partition \n\
      -a Linux (ext4) partition" 0 40
  fdisk -l | grep 'Disk /dev/.*' | grep -v 'Disk /dev/loop.*' | grep -o '.*GiB' | cut -d' ' -f2- > $part_list

  if whiptail --title "Create Partition" --yesno "Do you want to check for existing EFI partitions?\
  \nWARNING: if an EFI partition is present, rewriting it could break any other OS utilizing said partition.\
  \n\nDo you want to continue?" 13 55 3>&1 1>&2 2>&3; then
    while read -r part; do
    	checkEfiFileSystem "$part" $EFI_COUNTER
	    if [ $EFI_STATUS -eq 0 ]
	    then
	    	echo $EFI_PARTS
        EFI_COUNTER=$((EFI_COUNTER + 1))
        echo "EFI Counter: $EFI_COUNTER"
	    else
	    	echo "No EFI"
	    fi
    done < $part_list
  else
    whiptail --title "Create Partition" --msgbox "Skipping EFI Partition scan" 8 23 3>&1 1>&2 2>&3
    local efi_check=0
  fi
  selectInstallDisk $part_list
  wipeDisk $INSTALL_DISK
  if [ "$EFI_PART" = "" ]; then
    createEfiPartition
    createLinuxPartition
    createEfiFileSystem
    createLinuxFileSystem
  else
    createLinuxPartition
    createLinuxFileSystem
  fi

  mount $LINUX_PART /mnt
  if [ $? -eq 0 ]; then
    echo "/mnt mount successful"
  else
    error "/mnt mount failed! Exiting..."
  fi
  mkdir /mnt/efi
  mount $EFI_PART /mnt/efi
  if [ $? -eq 0 ]; then
    echo "/mnt/efi mount successful"
  else
    error "/mnt/efi mount failed! Exiting..."
  fi
}

checkGraphics() {
  lspci | grep VGA > lspci.txt
  vendors=("amd" "nvidia" "intel")
  for vendor in "${vendors[@]}"; do
    if [ $(cat lspci.txt | grep -i $vendor; echo $?) -eq 0 ]; then
      driver=$vendor
    fi
  done
  rm lspci.txt
  if [ "$driver" = "amd" ]; then
    echo "xf86-video-amdgpu"
    exit 0
  fi
  if [ "$driver" = "nvidia" ]; then
    echo "nvidia"
    exit 0
  fi
  if [ "$driver" = "intel" ]; then
    echo "mesa"
    exit 0
  fi
  if [ "$driver" = "" ]; then
    exit 1;
  fi
}

installBasePackages() {
  pacstrap_list="pacstrap.csv"
  curl $LINK/$pacstrap_list -o $pacstrap_list
  driver="$(checkGraphics)"
  if [ "$driver" != "" ]; then
    pacstrap /mnt "$driver"
  fi
  while read -r program; do
    pacstrap /mnt "$program"
  done < $pacstrap_list
}

installAurHelper() {
  arch-chroot /mnt /bin/bash -c 'pacman -S fakeroot --noconfirm'
  arch-chroot /mnt /bin/bash -c 'su - '"$USER"' -c "cd /home/'"$USER"' && sudo rm -rf yay && /usr/bin/git clone '"$AUR_HELPER"' && cd yay/ && sudo -u p0ndaa makepkg --syncdeps --needed --noconfirm && sudo -u p0ndaa makepkg -si PKGBUILD"'
}

pacmanInstall(){
  arch-chroot /mnt /bin/bash -c 'pacman -S '"$1"' --noconfirm'
}

aurHelperInstall() {
  arch-chroot /mnt /bin/bash -c 'sudo -u '"$USER"' yay -S '"$1"' --noconfirm'
}

makeInstall() {
  arch-chroot /mnt /bin/bash -c 'su - '"$USER"' -c "cd '"$REPO_DIR"' && /usr/bin/git clone '"$1"' && cd $_ && sudo -u '"$USER"' make clean install"'
}

generateFstab() {
  genfstab -U /mnt >> /mnt/etc/fstab
}

activateServices() {
  arch-chroot /mnt /bin/bash -c 'systemctl enable NetworkManager'
  arch-chroot /mnt /bin/bash -c 'systemctl enable bluetooth'
  arch-chroot /mnt /bin/bash -c 'systemctl enable bluetooth'
}

generateHostnameAndUser(){
  HOSTNAME=$(whiptail --title "Choose a hostname" --inputbox "Choose a hostname (your PC name)" 12 22 3>&1 1>&2 2>&3) || exit 1
  USER=$(whiptail --title "Choose an username " --inputbox "Choose an username for your user" 12 22 3>&1 1>&2 2>&3) || exit 1
  user_pass1=$(whiptail --nocancel --passwordbox "Enter a password for the user." 10 60 3>&1 1>&2 2>&3)
  user_pass2=$(whiptail --nocancel --passwordbox "Repeat the password" 10 60 3>&1 1>&2 2>&3)
  while ! [ "$user_pass1" = "$user_pass2" ]; do
    unset user_pass2
    user_pass1=$(whiptail --nocancel --passwordbox "Passwords do not match\nPlease try again" 10 60 3>&1 1>&2 2>&3)
    user_pass2=$(whiptail --nocancel --passwordbox "Repeat the password" 10 60 3>&1 1>&2 2>&3)
  done
}

generateRootPassword() {
  whiptail --title "Root password" --msgbox "You will be asked to enter root password now" 10 10 3>&1 1>&2 2>&3
  root_pass1=$(whiptail --nocancel --passwordbox "Enter a password for the root." 10 60 3>&1 1>&2 2>&3)
  root_pass2=$(whiptail --nocancel --passwordbox "Repeat the password" 10 60 3>&1 1>&2 2>&3)
  while ! [ "$root_pass1" = "$root_pass2" ]; do
    unset root_pass2
    root_pass1=$(whiptail --nocancel --passwordbox "Passwords do not match\nPlease try again" 10 60 3>&1 1>&2 2>&3)
    root_pass2=$(whiptail --nocancel --passwordbox "Repeat the password" 10 60 3>&1 1>&2 2>&3)
  done
}

addRootPassword() {
  arch-chroot /mnt /bin/bash -c 'echo root:'"$root_pass1"' | chpasswd'
  unset root_pass1 root_pass2
}

addUser(){
  arch-chroot /mnt /bin/bash -c 'useradd -mG wheel,audio,video '"$USER"''
  #export REPO_DIR="/home/$USER/.local/src"
  REPO_DIR="/home/$USER/.local/share"
  PATH_SCRIPT="/home/$USER/.local/bin"
  cp $0 /mnt/$REPO_DIR
  arch-chroot /mnt /bin/bash -c 'echo '"$USER"':'"$user_pass1"' | chpasswd'
  arch-chroot /mnt /bin/bash -c "mkdir -p '"$REPO_DIR"'"
  arch-chroot /mnt /bin/bash -c "mkdir -p '"$PATH_SCRIPT"'"
  arch-chroot /mnt /bin/bash -c 'su - '"$USER"' -c "mkdir -p {Documents,Pictures,Videos,Projects,Downloads,Music}"'
  arch-chroot /mnt /bin/bash -c 'chown -R '"$USER"':wheel $(dirname '"$REPO_DIR"') '
  arch-chroot /mnt /bin/bash -c 'export PATH=$PATH:'"$PATH_SCRIPT"''
  unset user_pass1 user_pass2
}

createFakeRoot() {
  sudoers_line="p0ndaa ALL=(ALL:ALL) NOPASSWD: ALL"
  echo "$sudoers_line" | arch-chroot /mnt /bin/bash -c 'tee -a /etc/sudoers'
}

deleteFakeRoot() {
  sudoers_line="p0ndaa ALL=(ALL:ALL) NOPASSWD: ALL"
  arch-chroot /mnt /bin/bash -c 'sed -i "/'"$sudoers_line"'/d" /etc/sudoers'
}

chrootSettings() {
  arch-chroot /mnt /bin/bash -c 'ln -sf "/usr/share/zoneinfo/'"$TIMEZONE"' /etc/localtime"'
  arch-chroot /mnt /bin/bash -c "sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen"
  arch-chroot /mnt locale-gen
  arch-chroot /mnt /bin/bash -c "echo "LANG=en_US.UTF-8" >> /etc/locale.conf"
  arch-chroot /mnt /bin/bash -c "echo "$HOSTNAME" >> /etc/hostname"
  arch-chroot /mnt /bin/bash -c "printf "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t$HOSTNAME.local\t$HOSTNAME" >> /etc/hosts"
  whiptail --title "sudo rights" --msgbox "In the following file, you have to uncomment\nthe wheel group. You should look for the wheel group\nwhich requires password.\nDO NOT UNCOMMENT THE LINE WITHOUT A PASSWORD\n\n# %wheel ALL=(ALL:ALL) ALL\n\nbecomes\n\n%wheel ALL=(ALL:ALL) ALL" 20 40
  arch-chroot /mnt /bin/bash -c "export EDITOR=vim && visudo"
   mount -t proc /proc /mnt/proc
  # mount --rbind /sys /mnt/sys
  # mount --rbind /dev /mnt/dev
  arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB $EFI_PART
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
  echo "grubconfigured"
}

installationLoop() {
  install_list="program-list.csv"
  curl $LINK/$install_list -o $install_list
  local total_lines=$(wc -l < "$install_list")
  local count=0
  while IFS=, read -r tag program; do
    ((count++))
    case "$tag" in
      "P") pacmanInstall "$program" 2>&1 > /dev/null;;
      "A") aurHelperInstall "$program" 2>&1 > /dev/null;;
      "M") makeInstall "$program" 2>&1 > /dev/null;;
    esac
    echo $((count * 100 / total_lines))
  done < $install_list #| whiptail --gauge "Installation Progress" 7 50 0 3>&1 1>&2 2>&3
  activateServices
}

prepareXinit() {
  arch-chroot /mnt /bin/bash -c 'echo "exec dwm" > /home/'"$USER"'/.xinitrc' 
}

#
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%........SCRIPT.......%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

loadKeymap 
setTimeZone || error "Timezone not selected"
createDisk || error "Disk not created"
generateHostnameAndUser|| error "Failed generating user"
generateRootPassword
installBasePackages || error "Failed installing base packages"
addUser || error "Failed adding user"
addRootPassword
createFakeRoot
generateFstab || (error "Failed generating fstab"&& exit 1)
chrootSettings || (error "Failed to execute commands in chroot"&& exit 1)
installAurHelper
installationLoop
deleteFakeRoot
prepareXinit

umount -R /mnt
# reboot
