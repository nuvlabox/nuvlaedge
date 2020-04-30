#!/bin/sh

apt-get update
apt-get install -y inotify-tools ntfs-3g usbmount wget jq

# might defer depending on the systemd-udev installed:
sed -i 's/PrivateMounts=yes/PrivateMounts=no/' /lib/systemd/system/systemd-udevd.service

systemctl daemon-reload
systemctl restart systemd-udevd

# Beware of the acceptable filesystem types by usbmount