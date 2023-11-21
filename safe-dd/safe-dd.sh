#!/bin/bash

saveCurrentDisks() {
  lsblk | tr -s ' ' | cut -d' '  -f1 > /tmp/safe-dd_conf.txt
  echo "Current configuration saved"
}

diskChecker() {
  while true; do
    clear
    printf "%s\n" "Wait for your disk to appear"
    printf "%s\n" "----------------------------"
    difference=$(diff <(cat /tmp/safe-dd_conf.txt) <(lsblk | tr -s ' ' | cut -d' ' -f1))
    result=$?
    if [ $result -ne 0 ]; then
      echo "Scan Successful"
      echo "$difference"
      break;
    else
      echo -en "Rescanning in: "
      for i in {5..1}; do
        echo -n "$i..."
        sleep 1
      done
    fi
  done
}

saveCurrentDisks
diskChecker
