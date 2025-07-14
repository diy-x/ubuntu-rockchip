#!/bin/env bash
MARKER_FILE="/etc/change_hostname_done"
if [ -f "$MARKER_FILE" ]; then
    echo hostname already changed
    exit 0
fi
NEW_HOSTNAME="hm$(date +%Y%m%d%H%M%S)"

hostnamectl set-hostname "$NEW_HOSTNAME"
echo "hostname changed to $NEW_HOSTNAME"
touch "$MARKER_FILE"
systemctl disable hostname-renamer.service
