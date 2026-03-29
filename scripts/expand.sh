#!/bin/bash
# This script must be run as root! (e.g. with sudo)
# This assumes the default partition layout is unchanged, and an encrypted ext4 filesystem is in use.

growpart /dev/sda 3
cryptsetup resize dm_crypt-0
pvresize /dev/mapper/dm_crypt-0
lvresize -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv

