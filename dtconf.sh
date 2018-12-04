#!/usr/bin/env bash

function init_dtconf {
    # Determine module Toradex 4 digit product ID
    PRODUCT_ID="$(tr -d '\0' </proc/device-tree/toradex,product-id)"

case "${PRODUCT_ID}" in
    "0039")
        MMCBLCKBOOT="mmcblk1boot0"
        BOOT_PART="/dev/mmcblk1p1"
    ;;
    "0027"|"0028"|"0029"|"0035")
       MMCBLCKBOOT="mmcblk2boot0"
       BOOT_PART="/dev/mmcblk2p1"
    ;; 
    "0014"|"0015"|"0017")
       MMCBLCKBOOT="mmcblk1boot0"
       BOOT_PART="/dev/mmcblk1p1"
    ;; 
    *)
        echo "Unsupported device"
        exit 1
    ;;
esac
}

# Give fw_setenv mmcblk0boot0 write permissions
function fw_setenv {
    touch /mnt/part/overlays.txt
    echo "fdt_overlays=$@" > /mnt/part/overlays.txt
    sync
}

function copy_env_config {
    # TODO: fix this for each platform. Or find a better way of doing it
    rm -rf /etc/fw_env.config
    touch /etc/fw_env.config
    echo "/dev/${MMCBLCKBOOT}       -0x2200    0x2000" > /etc/fw_env.config
}

function usage {
    echo "Usage: dtconf <command> [options]
    commands:
        -h,--help
        -o,--overlay [active <dtbo files>] [clear] [verify <dtbo file> [base dtb file]]
        -d,--devicetree [active <dtb file>]
        -b,--build <input dts_file> [out(dtb) name]
        -s,--status
        -p,--print <dtb file>
        -a,--activate <dtb file>
    "
}

function long_usage {
    usage
    echo "
        overlay:
            Print just the status of overlay specific items on the system
            [active] ---- Specify dtbo file(s) to be applied on boot
            [clear]  ---- Remove all active overlays. Nothing will be applied on boot.
            [verify] ---- Attempt to apply overlay to dtb file.
                            By default, overlay is verified against the active 
                            device-tree
        devicetree:
            Print just the status of the device-trees on the system
            [active] ---- Specify the device-tree (.dtb) file used on boot
        build: 
            Compile a device tree or overlay. 
            By default, the output filename is the same as the input filename
            with the swapped '.dts' file extension
        status:
            Print existing state of device trees and overlays.
            Also print any device trees/overlays found on the system
        print:
            Print out the human readable version of dtb. 
            This is for debugging. Output file is not a valid dts.
        activate:
            Builds, verifys and applys overlay if it's valid.
    "
}

# TODO: Deal with platform specifics
BOOT_MNT=/mnt/part

function mount_part {
    if ! $(mountpoint -q ${BOOT_MNT}); then
        echo "Mounting ${BOOT_PART}..."
        mkdir -p ${BOOT_MNT}
        if ! mount ${BOOT_PART} ${BOOT_MNT} ; then
            echo "Failed to mount ${BOOT_PART} to ${BOOT_MNT}"
        fi
    fi
    mkdir -p ${BOOT_MNT}/fdt_overlays
}

function active_overlays {
    env_string=$(cat ${BOOT_MNT}/overlays.txt)
    IFS='=' read -r -a pieces <<< "$env_string"
    echo ${pieces[1]}
}

function print_active_dt {
    env_string=$(fw_printenv |grep "fdtfile=")
    if [ -z "${env_string}" ]; then
        echo "Could not find active device tree. Provide active device" 
        exit 1
    fi
    IFS='=' read -r -a pieces <<< "$env_string"
    echo ${pieces[1]}
}

function devicetree_status {
    echo "== Active Device Tree:"
    print_active_dt
    echo ""
    echo "== System Device Trees:"
    files=$(ls -1 ${BOOT_MNT}/*.dtb 2> /dev/null)
    if [ -z "${files}" ];then
        echo "No Device Trees Found"
    else
        for f in ${files}
        do
            echo ${f}
        done
    fi
}

function overlay_status {
    echo "== Active Overlays:"
    files=$(active_overlays)
    if [ -z "${files}" ];then
        echo "No Active Overlays"
    else
        for f in $files
        do
            echo $f
        done
    fi
    echo ""
    echo "== System Overlays:"
    files=$(ls -1 ${BOOT_MNT}/fdt_overlays/*.dtbo 2> /dev/null)
    if [ -z "${files}" ];then
        echo "No Overlays Found"
    else
        for f in ${files}
        do
            echo ${f}
        done
    fi
    echo ""
    echo "== Other Overlays:"
    files=$(ls -1 ${DT_SANDBOX}/overlays/*.dtbo 2> /dev/null)
    if [ -z "${files}" ];then
        echo "No Overlays Found"
    else
        for f in ${files}
        do
            echo ${f}
        done
    fi
}

function build_dtb {
    if [ $# -lt 1 ];then
        echo "Specify input dts file"
        exit -1;
    fi

    INPUT_DTS=$1
    FILE_EXT=".dtb"
    # Determine whether or not we are building .dtbo or .dtb
    if $(grep "fragment@0" ${INPUT_DTS} &> /dev/null) ; then
        FILE_EXT=".dtbo"
    fi

    filename=$(basename -- "${INPUT_DTS}")
    filename="${filename%.*}"${FILE_EXT}

    # Optional 2nd parameter as the output file.
    if [ ! -z "$2" ];then
        filename=$2
    fi

    dtc -@ -I dts -O dtb -o ${filename} ${INPUT_DTS} || {
        echo "Failed to build device tree"
        exit
    }
    echo "Successfully Built Device Tree"
}

function verify_overlay {
    DTBO=$1
    DTB=$2

    # If dtb not specified we assume the active dtb
    if [ -z "$DTB" ];then
        ACTIVE_DEVICE_TREE=$(print_active_dt)
        DTB=${BOOT_MNT}/${ACTIVE_DEVICE_TREE}
    else
        DTB=${BOOT_MNT}/${DTB}
    fi

    # Save the output to /tmp... we dont care about it.
    if fdtoverlay -i ${DTB} -o /tmp/$(basename -- "$DTB").tmp ${DTBO} ; then
        echo "Overlay is Valid"
    else
        echo "Overlay Invalid!"
        exit -1;
    fi
}

function apply_overlays {

    if [ $# -lt 1 ];then
        echo "Specify input overlay file(s)"
        exit -1;
    fi

    OVERLAY_FILES=$@

    rm -rf ${BOOT_MNT}/fdt_overlays/*
    FILES_STRING=""

    for FILE in ${OVERLAY_FILES}
    do
        if [ ! -f ${FILE} ];then
            echo "${FILE} doesn't exist"
            exit -2
        fi
        cp ${FILE} ${BOOT_MNT}/fdt_overlays/

        FILES_STRING="${FILES_STRING} $(basename ${FILE})"
    done

    ### Set the overlays.txt file
    fw_setenv ${FILES_STRING} || {
        echo "Failed to write overlays.txt"
        exit -1
    }
    echo "A reboot is necessary for changes to take effect..."
}

function clear_overlays {
    # Set it to nothing
    echo "Clearing overlays"
    rm /mnt/part/overlays.txt 2>/dev/null
}

function apply_devicetree {
    if [ $# -ne 1 ];then
        echo "Specify input device-tree file"
        exit -1;
    fi
    # Copy device-tree (.dtb) to the boot partition
    cp $1 /${BOOT_MNT}/ || {
    exit errno
    }
    ### Set the uboot environment variable to pick up new device-tree
    fw_setenv fdtfile $(basename -- "$1") || {
        echo "Failed to set uboot environment variable"
        exit -1
    }
    echo "A reboot is necessary for changes to take effect..."
}

function activate_overlay
{
    CURRENT_OVERLAY=""
    OVERLAY_FILES=""

    while [ -n "${1}" ]; do 
        if [ "${1}" = "-c" ]; then
            shift  
            CURRENT_OVERLAY=${1}
        else
            OVERLAY_FILES="${OVERLAY_FILES} ${1}"
        fi
    shift
    done

    OVERLAYS=""

    for FILE in ${OVERLAY_FILES}
    do
        echo "Building ${FILE}"
        build_dtb ${FILE}
        echo "Verifying ${FILE}"
        verify_overlay ${filename} ${CURRENT_OVERLAY}
        OVERLAYS="${OVERLAYS} ${filename}"
    done
    echo "Applying overlays: ${OVERLAYS}"
    apply_overlays ${OVERLAYS}
}


init_dtconf
copy_env_config
mount_part

case "$1" in

    -h|--help)
        long_usage
        exit
        ;;

    -a|--activate)
        shift && activate_overlay $@
        ;;
        
    -o|--overlay)
        if [ $# -eq 1 ];then
            echo ""
            overlay_status
            exit
        elif [ $# -gt 2 ] && [ "$2" == "active" ]; then
            # Pass in 3rd arg onward
            shift && shift && apply_overlays $@
            exit
        elif [ $# -ge 2 ] && [ "$2" == "clear" ]; then
            clear_overlays
            exit
        elif [ $# -gt 2 ] && [ "$2" == "verify" ]; then
            shift && shift && verify_overlay $@
            exit
        else
            usage
            exit
        fi
        ;;

    -s|--status)
        devicetree_status
        echo ""
        overlay_status
        echo ""
        ;;

    -d|--devicetree)
        if [ $# -eq 1 ];then
            echo ""
            devicetree_status
            exit
        elif [ $# -gt 2 ] && [ "$2" == "active" ]; then
            shift && shift && apply_devicetree $@
        else
            usage
            exit
        fi
        ;;

    -b|--build)
        if [ $# -gt 1 ];then
            shift && build_dtb $@
        else
            usage
            exit
        fi
        ;;

    -p|--print)
        if [ $# -lt 2 ];then
            usage
            exit
        fi
        fdtdump $2
        ;;

    *)
        usage
        exit

esac
