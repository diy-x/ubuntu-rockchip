# shellcheck shell=bash
function install_training_assist_exp() {
    local rootfs="$1"
    local overlay="$2"
    echo "pre-install training_assist with rootfs:${rootfs} overlay:${overlay}"
    installerRepo="https://e.coding.net/g-hvab4800/train_assist/client_versions.git"
    VERSION_REGEX_MaSTER="^[0-9]+\.[0-9]+\.[0-9]+$"

    install_dir="/home/holomotion/local/bin"
    ntsport_dir="$install_dir/ntsports"
    program_dir="$ntsport_dir/client_versions"

    startup_bin="$install_dir/train_assist_client"
    startup_icon="$program_dir/train_assist_client.png"

    startup_src="$program_dir/train_assist_for_linux.sh"
    startup_app="$ntsport_dir/train_assist_for_linux.sh"

    install_src="$program_dir/train_assist_installer.sh"
    install_bin="$install_dir/train_assist_installer"
    install_app="$ntsport_dir/train_assist_installer.sh"

    set_wifi_src="$program_dir/set_wifi.sh"
    set_wifi_bin="$install_dir/set_wifi"
    set_wifi_app="$ntsport_dir/set_wifi.sh"


    chroot "${rootfs}" /bin/bash -c "[ -d $ntsport_dir ] || mkdir -p $ntsport_dir"

    cat <<-EOF >"${rootfs}${ntsport_dir}/branch.txt"
    master
EOF
    chroot "${rootfs}" git clone $installerRepo $program_dir
    chroot "${rootfs}" git config --global --add safe.directory $program_dir
    chroot "${rootfs}" /bin/bash -c "sudo -u holomotion git config --global --add safe.directory ${program_dir}"


    # get latest relase tag version
    latest_version=$(chroot "${rootfs}" /bin/bash -c "git -C $program_dir ls-remote --tags --refs origin | awk -F/ '{print \$3}' | grep -E '$VERSION_REGEX_MaSTER' | sort -t '-' -k 1,1V -k 2,2n | awk 'END{print}'")
    if echo "$latest_version" | grep -qE "$VERSION_REGEX_MaSTER"; then
        echo "got latest master version $latest_version"
        chroot "${rootfs}"  git -C $program_dir reset --hard "$latest_version"
    fi
    echo "check file $install_src in $rootfs"
    if [ -f "${rootfs}${install_src}" ]; then
        echo "copying ${install_src} to ${install_app} in ${rootfs}"
        chroot "${rootfs}"  cp -f "${install_src}" "${install_app}" >/dev/null 2>&1 || true
        echo "create soft link for $install_app  with target $install_bin"
        chroot "${rootfs}"  ln -s -f "$install_app" "$install_bin" >/dev/null 2>&1 || true
        chroot "${rootfs}"  chmod +x "$install_app" >/dev/null 2>&1 || true
    fi

    echo "check file $startup_src in $rootfs"
    if [ -f "${rootfs}${startup_src}" ];then
        echo "copying ${startup_src} to ${startup_app} in ${rootfs}"
        chroot "${rootfs}"  cp -f "${startup_src}" "${startup_app}" >/dev/null 2>&1 || true
        echo "create soft link for $startup_app  with target $startup_bin"
        chroot "${rootfs}"  ln -s -f "$startup_app" "$startup_bin" >/dev/null 2>&1 || true
        chroot "${rootfs}"  chmod +x "$startup_app" >/dev/null 2>&1 || true
    fi

    echo "check file $set_wifi_src in $rootfs"
    if [ -f "${rootfs}${set_wifi_src}" ];then
        echo "copying ${set_wifi_src} to ${set_wifi_app} in ${rootfs}"
        chroot "${rootfs}"  cp -f "${set_wifi_src}" "${set_wifi_app}" >/dev/null 2>&1 || true
        echo "create soft link for $set_wifi_app  with target $set_wifi_bin"
        chroot "${rootfs}"  ln -s -f "$set_wifi_app" "$set_wifi_bin" >/dev/null 2>&1 || true
        chroot "${rootfs}"  chmod +x "$set_wifi_app" >/dev/null 2>&1 || true
    fi

    mkdir -p "${rootfs}/usr/share/applications"
    # create desktop
    cat <<-EOF >"${rootfs}/usr/share/applications/train_assist_client.desktop"
    [Desktop Entry]
    Type=Application
    Name=训练机客户端
    GenericName=训练机客户端
    Comment=训练机客户端
    Exec="$startup_app" %f
    Icon=$startup_icon
    Terminal=true
    Categories=X-Application;
EOF

    # create startup run
    mkdir -p "${rootfs}/home/holomotion/.config/autostart"
    cat <<-EOF >"${rootfs}/home/holomotion/.config/autostart/train_assist_client.desktop"
    [Desktop Entry]
    Type=Application
    Name=训练机客户端
    GenericName=训练机客户端
    Comment=训练机客户端
    Exec="$startup_app" %f
    Icon=$startup_icon
    Terminal=true
    Categories=X-Application;
EOF

    chroot "${rootfs}" /bin/bash -c "chown -R holomotion:holomotion /home/holomotion"

    echo "setup custom wifi flag"
    custom_wifi_flag="/etc/features/enable_custom_wifi"
    cat <<-EOF >"${rootfs}${custom_wifi_flag}"
    true
EOF
    echo "add sudoer file"
    cat <<-EOF >"${rootfs}/etc/sudoers.d/custom_wifi"
holomotion ALL=(ALL) NOPASSWD: /usr/bin/killall,/usr/sbin/wpa_supplicant,/usr/sbin/wpa_cli,/usr/sbin/ip,/usr/bin/cat,/usr/bin/rm,/usr/bin/systemctl,/usr/sbin/iwlist,/usr/bin/bash,/sbin/dhclient,/usr/sbin/dhclient
EOF

    # echo  "remove screen keyboard..."
    # rm -rf "${rootfs}/home/holomotion/.config/autostart/caribou.desktop"
    # echo "remove caribou..."
    # chroot "${rootfs}" apt-get remove -y caribou

    echo "pre-install training assist completed"

    return 0
}