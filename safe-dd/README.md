# safe-dd

Are you not using dd because you fear deleting your filesystem?

safe-dd helps by saving the current disk configuration and detects when the new disk is connected.

End goal is to create a dd manipulation tool that blocks you from using the disks in use and only
allows the usage of newly connected disks (like USB).
It is useful for several cases, like burning your distro ISO to the USB.

# Currently implemented
- automatic detection

## To be implemented
- blocking system
- correct dd manipulation
- to be added...
