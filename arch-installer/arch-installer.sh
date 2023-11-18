# Remember to remove sudo from commands TODO
#
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%.....GLOBAL VARIABLES......%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
TIMEZONE=""
AUR_HELPER="yay"
EFI_PART=()
EFI_STATUS=""
EFI_SIZE=()
EFI_COUNTER=0
INSTALL_DISK=""

#
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%........FUNCTIONS........%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

# Used to exit the program
# shows the cause of crash
error() {
  printf '%s\n' "$1"
  return 1
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
  TIMEZONE=$(whiptail --title "Timezone" --menu "Select a timezone" 0 60 0 "${LIST_TIMEZONES[@]}" 3>&1 1>&2 2>&3)
  timedatectl set-timezone ${TIMEZONE}
	rm $time_file
}

# check for existing EFI filesystems
# works with "/dev/sdx" format 
# ---
# checkEfiFileSystem PARTITION
#
# return 0 --> success
# TODO: change fdisk to sfdisk
checkEfiFileSystem() {
  local part=$(printf "$1" | sed 's/:.*//')
  local checker=$(printf 'p' | fdisk $part | grep "EFI" | cut -d' ' -f1)
  
  if [ $(printf 'p' | fdisk "$part" | grep "EFI" >> /dev/null; printf $?) -eq 0 ]
  then
    EFI_PART+=("$checker")
    EFI_STATUS=0
    EFI_SIZE+=("$(printf 'p' | fdisk $part | grep "EFI" | tr -s ' ' | cut -d' ' -f5)")
    whiptail --title 'Alert' --msgbox \
    "Found an EFI partition on $part \nLocation: $checker \nSize: ${EFI_SIZE[$EFI_COUNTER]}" 10 40 3>&1 1>&2 2>&3
    printf "$part"
  else
    whiptail --title 'Alert' --msgbox \
    "No EFI partition found on $part" 10 40 3>&1 1>&2 2>&3
    EFI_STATUS=1
  fi
}

# check for existing Linux filesystems
# works with "/dev/sdx" format 
# ---
# checkLinuxFileSystem PARTITION
# 
# return 0 --> success
# TODO
# checkLinuxFileSystem() {
#   part=$($1 | sed 's/:.*//' | cut -d'/' -f3)
#   if [ $(printf 'p' | sudo fdisk $part | grep "Linux filesystem" >> /dev/null; printf $?) -eq 0 ]
#   then
#     whiptail --title "Alert" --msgbox "Found a Linux partition"
#   fi
# }

# select install disk
# takes part list file as input
# ---
# selectInstallDisk PART_LIST
selectInstallDisk() {
  local part_list=()
  local counter=0
  while read -r part; do
    local new_separator="$($part | sed 's/:/ -/')"
    if echo "$part" | grep -q "sd"; then
      if [ "$(echo "$part" | sed 's/:.*//')" = "$(echo "${EFI_PART[$counter]}" | sed 's/[0-9]*$//')" ]; then
        part_list+=("${part}" "   (EFI)")
        counter=$((counter+1))
      else
        part_list+=("${part}" "")
      fi
    fi
    if echo "$part" | grep -q "nvm"; then
      if [ "$(echo "$part" | sed 's/:.*//')" = "$(echo "${EFI_PART[$counter]}" | sed 's/[a-z][0-9]*$//')" ]; then
        part_list+=("${part}" "   (EFI)")
        counter=$((counter+1))
      else
        part_list+=("${part}" "")
      fi
    fi
  done < $1
  INSTALL_DISK=$(whiptail --title "Select disk" --menu "Select an installation disk" 0 60 20 "${part_list[@]}" 3>&1 1>&2 2>&3 | sed "s/:.*//")
}

# wipe all past signatures
wipePartitionSignature() {
  local part_file=""
	while read -r timezone; do
		LIST_TIMEZONES+=("${timezone}" "")
	done < $time_file
}

# create an EFI and Linux partition
createPartition() {
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
	  	echo $EFI_PART
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

  #if whiptail --title "Create Partition" --yesno "Do you want to check for existing Linux partitions?\
  #\n\nWARNING: if a Linux partition is present, rewriting will wipe the data present.\
  #\n\nDo you want to continue?" 13 55 3>&1 1>&2 2>&3; then
  #  while read -r part; do
  #  	checkLinuxFileSystem "$part" 
  #  done < fdisk-list.txt

  #fi
}

setTimeZone
createPartition

# echo -e "g\nn\n1\n\n+128M\nt\n1\nn\n2\n\n\nw" | fdisk ${INSTALL_DISK}


# create filesystems
#mkfs.fat -F32 ${EFI_PARTITION}
#mkfs.ext4 ${LINUX_PARTITION}

# moung created partitions
#mount ${LINUX_PARTITION} /mnt
#mkdir /mnt/efi
#mount ${EFI_PARTITION} /mnt/efi

# install base packages
# pacstrap /mnt base linux linux-firmware vim networkmanager grub efibootmgr sudo

# generate fstab
# genfstab -U /mnt >> /mnt/etc/fstab

# chroot into environment
# chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Vienna /etc/localtime

