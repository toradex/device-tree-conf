# Give fw_setenv mmcblk0boot0 write permissions
fw_setenv() {
    echo 0 > /sys/block/mmcblk2boot0/force_ro
    /usr/sbin/fw_setenv "$@"
    sync
    echo 1 > /sys/block/mmcblk2boot0/force_ro
}
