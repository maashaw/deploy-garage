sudo growpart /dev/sda 3
sudo cryptsetup resize dm_crypt-0
sudo pvresize /dev/mapper/dm_crypt-0
sudo lvresize -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
