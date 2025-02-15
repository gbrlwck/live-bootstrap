#!/usr/bin/bash

# SPDX-FileCopyrightText: 2021 fosslinux <fosslinux@aussies.space>
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -e

# shellcheck source=sysglobal/helpers.sh
. helpers.sh
# shellcheck source=/dev/null
. bootstrap.cfg

export PATH=/usr/bin:/usr/sbin

# Unload the current kernel before things go weird
kexec -u

create_hdx() {
    # Create all of the sd{a,b,c..}
    minor=0
    alpha="a b c d e f g h i j k l m n o p" # 16 disks -- more than enough
    # For each disk...
    for a in ${alpha}; do
        mknod -m 600 "/dev/sd${a}" b 8 "$((minor++))"
        # For each partition...
        for p in $(seq 15); do
            mknod -m 600 "/dev/sd${a}${p}" b 8 "$((minor++))"
        done
    done
}

# All the various structures that don't exist but needed to mount
mkdir -p /etc /dev
populate_device_nodes ""
create_hdx

ask_disk() {
    echo
    echo "What disk would you like to use for live-bootstrap?"
    echo "(live-bootstrap assumes you have pre-prepared the disk)."
    echo "Please provide in format sdxx (as you would find under /dev)."
    echo "You can type 'list' to get a list of disks to help you figure"
    echo "out which is the right disk."
    echo
    read -r DISK

    if [ "${DISK}" = "list" ]; then
        fdisk -l
        ask_disk
    elif [ -z "${DISK}" ] || ! [ -e "/dev/${DISK}" ]; then
        echo "Invalid."
        ask_disk
    fi
}

if [ -z "${DISK}" ] || ! [ -e "/dev/${DISK}" ]; then
    echo "You did not provide a valid disk in the configuration file."
    ask_disk
fi

echo "export DISK=${DISK}" >> /usr/src/bootstrap.cfg

# Otherwise, add stuff from sysa to sysb
echo "Mounting sysc"
mkdir /sysc
mount -t ext4 "/dev/${DISK}" /sysc

# Copy over appropriate data
echo "Copying data into sysc"
cp -r /dev /sysc/
# Don't include /usr/src
find /usr -mindepth 1 -maxdepth 1 -type d -not -name src -exec cp -r {} /sysc/{} \;
# Except for bootstrap.cfg
cp /usr/src/bootstrap.cfg /sysc/usr/src/bootstrap.cfg
sync

# switch_root into sysc 1. for simplicity 2. to avoid kexecing again
# spouts a few errors because we don't have /proc /sys or /dev mounted
echo "Switching into sysc"
exec switch_root /sysc /init
