#!/bin/env bash
if [ "$EUID" -ne 0 ]; then
  echo "please run this script with sudo"
  exit 1
fi

echo "disable wayland for login"
sed -i '/WaylandEnable=false/ s/^[[:space:]]*#[[:space:]]*//'  /etc/gdm3/custom.conf

echo "apply screen CalibrationMatrix"
sed -i '/Identifier "libinput touchscreen catchall"/,/EndSection/ {
    /Identifier "libinput touchscreen catchall"/ a\        Option "CalibrationMatrix" "0 -1 1 1 0 0 0 0 1"
}'  /usr/share/X11/xorg.conf.d/40-libinput.conf

echo "done.you should reboot to take effect."