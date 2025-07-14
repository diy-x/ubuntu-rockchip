# shellcheck shell=bash
function quick-setup() {
    local rootfs="$1"
    local overlay="$2"
    echo "run quick setup script with rootfs:${rootfs} overlay:${overlay}"

    # Install dotnet runtime
    chroot "${rootfs}" add-apt-repository -y ppa:dotnet/backports
    chroot "${rootfs}" apt-get  install -y  dotnet-runtime-7.0

    # Install other packages
    chroot "${rootfs}" apt-get  install -y lrzsz unclutter-xfixes gnome-shell-extension-desktop-icons-ng gnome-shell-extension-prefs libmpv-dev mpv ipcalc  mpg123 espeak-ng  git libx264-dev xclip  unity-control-center cockpit wireless-tools wpasupplicant net-tools gawk zbar-tools isc-dhcp-client

    if [  -d "${rootfs}/tmp" ]; then
        rustdesk_installer_url="https://github.com/rustdesk/rustdesk/releases/download/1.2.3-2/rustdesk-1.2.3-2-aarch64.deb"
        deb_save_path="/tmp/rustdesk-1.2.3-2-aarch64.deb"

        # download rustdesk binary
        if wget  "${rustdesk_installer_url}" -O "${rootfs}${deb_save_path}"; then
            # ensure dpkg exist
            chroot "${rootfs}" apt-get install -y dpkg libxdo3
            chroot "${rootfs}" dpkg -i "${deb_save_path}"
            rm -rf "${rootfs}${deb_save_path}"
            # install rustdesk check service
            mkdir -p "${rootfs}/usr/lib/scripts/"
            cp "${overlay}/usr/lib/systemd/system/rustdesk-config-checker.service" "${rootfs}/usr/lib/systemd/system/rustdesk-config-checker.service"
            cp "${overlay}/usr/lib/scripts/rustdesk-config-checker.sh" "${rootfs}/usr/lib/scripts/rustdesk-config-checker.sh"
            chroot "${rootfs}" systemctl enable rustdesk-config-checker
        else
            echo "Failed to download RustDesk installer"
        fi
    fi
    # add forwarder service
    local api_url="https://api.github.com/repos/holomotion/forwarder/releases/latest"
    # Use curl to fetch the latest release information and parse the JSON response with grep and awk
    # shellcheck disable=SC2155
    local forwarder_latest_tag=$(curl -s "$api_url" | grep -m 1 '"tag_name":' | awk -F '"' '{print $4}')
    # Check if latest_tag is null or empty
    if [ -n "$forwarder_latest_tag" ]; then
        echo "the forwarder latest release tag for  is: $forwarder_latest_tag"
        mkdir -p "${rootfs}/usr/bin"
        forwarder_download_url="https://github.com/holomotion/forwarder/releases/download/$forwarder_latest_tag/forwarder-aarch64-unknown-linux-musl.zip"
        forwarder_save_path="${rootfs}/tmp/forwarder.zip"
        if wget  "${forwarder_download_url}" -O "${forwarder_save_path}"; then
            unzip "${forwarder_save_path}" -d "${rootfs}/usr/bin/"
            rm "${forwarder_save_path}"
        fi
        cp "${overlay}/usr/lib/systemd/system/forwarder.service" "${rootfs}/usr/lib/systemd/system/forwarder.service"
        chroot "${rootfs}" systemctl enable forwarder
    fi


    # add rotateopt tool
    local api_url="https://api.github.com/repos/holomotion/rotateopt/releases/latest"
    # Use curl to fetch the latest release information and parse the JSON response with grep and awk
    # shellcheck disable=SC2155
    local rotateopt_latest_tag=$(curl -s "$api_url" | grep -m 1 '"tag_name":' | awk -F '"' '{print $4}')
    # Check if latest_tag is null or empty
    if [ -n "$rotateopt_latest_tag" ]; then
        echo "the rotateopt latest release tag for  is: $rotateopt_latest_tag"
        mkdir -p "${rootfs}/usr/bin"
        rotateopt_download_url="https://github.com/holomotion/rotateopt/releases/download/$rotateopt_latest_tag/rotateopt-aarch64-unknown-linux-musl.zip"
        rotateopt_save_path="${rootfs}/tmp/rotateopt.zip"
        if wget  "${rotateopt_download_url}" -O "${rotateopt_save_path}"; then
            unzip "${rotateopt_save_path}" -d "${rootfs}/usr/bin/"
            rm "${rotateopt_save_path}"
        fi
    fi


    # add custom theme to change the bootlogo
    THEME_PLYMOUTH="/usr/share/plymouth/themes/holomotion/holomotion.plymouth"
    cp -r "${overlay}/usr/share/plymouth/themes/holomotion" "${rootfs}/usr/share/plymouth/themes/"
    chroot "${rootfs}" update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth $THEME_PLYMOUTH 150
    chroot "${rootfs}"  update-alternatives --set default.plymouth $THEME_PLYMOUTH

    # copy wallpapers
    mkdir -p "${rootfs}/usr/share/backgrounds"
    cp  "${overlay}/usr/share/backgrounds/holomotion_h.png" "${rootfs}/usr/share/backgrounds/holomotion_h.png"
    cp  "${overlay}/usr/share/backgrounds/holomotion_v.jpg" "${rootfs}/usr/share/backgrounds/holomotion_v.jpg"
    chroot "${rootfs}" chmod -R 755 /usr/share/backgrounds/
    # setup cockpit info
    cat <<-EOF >"${rootfs}/etc/issue.cockpit"
    for more info about Holomotion,plese visit:https://holomotion.tech . you can contact us with support@ntsports.tech
EOF

    cat <<-EOF >"${rootfs}/etc/cockpit/cockpit.conf"
    [WebService]
    LoginTitle=Holomotion Device Portal
    [Session]
    Banner=/etc/issue.cockpit
EOF

    # change timezone
    cat <<-EOF >"${rootfs}/etc/timezone"
    Asia/Shanghai
EOF
    chroot "${rootfs}" rm /etc/localtime
    chroot "${rootfs}" ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    # change hostname
    cp "${overlay}/usr/lib/systemd/system/hostname-renamer.service" "${rootfs}/usr/lib/systemd/system/hostname-renamer.service"
    cp "${overlay}/usr/lib/scripts/hostname-renamer.sh" "${rootfs}/usr/lib/scripts/hostname-renamer.sh"
    # ensure script have execute permission
    chmod +x "${rootfs}/usr/lib/scripts/hostname-renamer.sh"
    chroot "${rootfs}" systemctl enable hostname-renamer

    # firstboot options apply
    cp "${overlay}/usr/lib/systemd/system/firstboot-options-apply.service" "${rootfs}/usr/lib/systemd/system/firstboot-options-apply.service"
    cp "${overlay}/usr/lib/scripts/firstboot-options-apply.sh" "${rootfs}/usr/lib/scripts/firstboot-options-apply.sh"
    chroot "${rootfs}" systemctl enable firstboot-options-apply

    # disable setup wizard:
    chroot "${rootfs}" systemctl disable oem-config.service
    chroot "${rootfs}" systemctl disable oem-config.target
    chroot "${rootfs}" apt-get remove -y oem-config-gtk ubiquity-frontend-gtk ubiquity-slideshow-ubuntu
    chroot "${rootfs}" rm -rf /var/lib/oem-config
    # optional:set password expire after login
    # chroot "${rootfs}" chage -d 0 holomotion

    # remove oem user
    if id "oem" &>/dev/null; then
        echo "try to remove oem user"
        if userdel -r "oem";then
            echo "user oem was deleted"
        else
            echo "failed to remove user oem."
        fi
    else
        echo "user oem does not exist,no need to process"
    fi

    chroot "${rootfs}" mkdir -p /etc/skel/.config
    chroot "${rootfs}" mkdir -p /etc/skel/{Desktop,Documents,Downloads,Music,Pictures,Videos}
    printf yes | chroot "${rootfs}" tee /etc/skel/.config/gnome-initial-setup-done
    echo "en_US" | chroot "${rootfs}" tee /etc/skel/.config/user-dirs.locale
    echo "set user to use english dir name"
    chroot "${rootfs}" cat <<-EOF >"/etc/skel/.config/user-dirs.dirs"
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
EOF
    chroot "${rootfs}" cat <<-EOF >"/etc/xdg/user-dirs.defaults"
DESKTOP=Desktop
DOCUMENTS=Documents
DOWNLOAD=Downloads
MUSIC=Music
PICTURES=Pictures
PUBLICSHARE=Public
TEMPLATES=Templates
VIDEOS=Videos
EOF


    # pre create user and set autologin
    chroot "${rootfs}" useradd -m -s "/bin/bash" "holomotion"
    echo "holomotion:holomotion" | chroot "${rootfs}" /bin/bash -c "chpasswd"
    chroot "$rootfs" usermod -aG sudo "holomotion"
    echo "update use dirs settings"
    chroot "$rootfs" sudo -u holomotion LANG=en_US.UTF-8 xdg-user-dirs-update --force
    user_groups="adm cdrom dip video plugdev users lpadmin"
    for ug in $user_groups;
    do
        if chroot "$rootfs" getent group "$ug" > /dev/null 2>&1; then
            chroot "$rootfs"  usermod -aG "$ug" "holomotion"
            echo "User holomotion added to group $ug."
        else
            echo "Group $ug does not exist."
        fi
    done

    # setup home dir for the new user
    if ! chroot "${rootfs}" test -d /home/holomotion; then
        chroot "$rootfs" mkdir -p "/home/holomotion"
        echo "pre-create dirs in user-home"
        chroot "$rootfs" mkdir  /home/holomotion/{Desktop,Documents,Downloads,Music,Pictures,Videos}
        chroot "${rootfs}" /bin/bash -c "chown -R holomotion:holomotion /home/holomotion"
    else
        echo "/home/holomotion already exists, skipping directory creation"
    fi

    echo "fix chown for holomotion user"
    chroot "${rootfs}" /bin/bash -c "chown -R holomotion:holomotion /home/holomotion"

    # chinese config
    chroot "${rootfs}" apt-get  install -y   language-pack-zh-hant language-pack-zh-hans language-pack-gnome-zh-hant language-pack-gnome-zh-hans  fonts-wqy-microhei fonts-wqy-zenhei im-config ibus ibus-pinyin ibus-clutter ibus-gtk ibus-gtk3
    # Configure the system language to Chinese (Simplified)
    chroot "${rootfs}" update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh

    # Set Chinese as the preferred language system-wide
    cat <<-EOF >"${rootfs}/etc/default/locale"
    LANG=zh_CN.UTF-8
    LANGUAGE=zh_CN:zh
EOF
    # Set ibus as the default input method
    cat <<-EOF >>"${rootfs}/etc/environment"
    GTK_IM_MODULE=ibus
    QT_IM_MODULE=ibus
    CLUTTER_IM_MODULE=ibus
    XMODIFIERS=@im=ibus
EOF

    chroot "${rootfs}" im-config -n ibus

    #set ibus auto run
    mkdir -p "${rootfs}/home/holomotion/.config/autostart"
    cat <<-EOF >"${rootfs}/home/holomotion/.config/autostart/ibus.desktop"
    [Desktop Entry]
    Type=Application
    Exec=ibus-daemon -drx
    Hidden=false
    NoDisplay=false
    X-GNOME-Autostart-enabled=true
    Name=ibus
    Comment=Start ibus input method framework
EOF

    # copy cockpit files plugin
    echo "install cockpit files extensions"
    echo "creating dir..."
    mkdir -p "${rootfs}/usr/local/share/cockpit/files"
    echo "extract cockpit files to dir"
    unzip "${overlay}/usr/share/cockpit/cockpit-files-17.zip" -d "${rootfs}/usr/local/share/cockpit/files"

    # install and enable shell extensions
    echo "copying shell extensions"
    mkdir -p "${rootfs}/usr/share/shellextensions"
    cp "${overlay}/usr/share/shellextensions/disable-gestures-three-fingers.shell-extension.zip" "${rootfs}/usr/share/shellextensions/disable-gestures-three-fingers.shell-extension.zip"

    #pre-install NT.Tool
    nt_tool_download_url="https://github.com/holomotion/NT.Tool/releases/download/v1.0.0/NT.Tool.zip"
    nt_tool_save_path="${rootfs}/tmp/nt.tool.zip"
    if wget  "${nt_tool_download_url}" -O "${nt_tool_save_path}"; then
        mkdir "${rootfs}/opt/NT.Tool"
        unzip "${nt_tool_save_path}" -d "${rootfs}/opt/NT.Tool/"
        rm "${nt_tool_save_path}"
        chroot "${rootfs}" /bin/bash -c "chown -R holomotion:holomotion /opt/NT.Tool/"
        chroot "${rootfs}" /bin/bash -c "chmod +x /opt/NT.Tool/NT.Tool"
        chroot "${rootfs}" /bin/bash -c "chmod +x /opt/NT.Tool/NT.Tool.sh"
        cat <<-EOF > "${rootfs}/usr/share/applications/NT.Tool.desktop"
      [Desktop Entry]
      Type=Application
      Name=NT.Tool
      Exec=/opt/NT.Tool/NT.Tool.sh
      Icon=/opt/NT.Tool/icon.png
      Terminal=false
      Categories=Utility;
EOF
        chmod +x "${rootfs}/usr/share/applications/NT.Tool.desktop"

    fi



    # Apply system-wide language changes
   # {
   #     echo "export LC_ALL=zh_CN.UTF-8"
   #     echo "export LANG=zh_CN.UTF-8"
   #        echo "export LANGUAGE=zh_CN:zh"
   #} >> "${rootfs}/etc/profile"

    # create caribou screen keyboard startup
#     cat <<-EOF >"${rootfs}/home/holomotion/.config/autostart/caribou.desktop"
#     [Desktop Entry]
#     Type=Application
#     Exec=caribou
#     Hidden=false
#     NoDisplay=false
#     X-GNOME-Autostart-enabled=true
#     Name=Caribou
#     Comment=On-screen keyboard
# EOF

    # uncomment logind.conf to set power options
    LOGIND_CONF="${rootfs}/etc/systemd/logind.conf"
    sed -i 's/^#*\(HandleLidSwitch=\).*/\1ignore/' "${LOGIND_CONF}"
    sed -i 's/^#*\(HandleLidSwitchDocked=\).*/\1ignore/' "${LOGIND_CONF}"
    sed -i 's/^#*\(HandleLidSwitchExternalPower=\).*/\1ignore/' "${LOGIND_CONF}"
    sed -i 's/^#*\(HandleSuspendKey=\).*/\1ignore/' "${LOGIND_CONF}"
    sed -i 's/^#*\(HandleHibernateKey=\).*/\1ignore/' "${LOGIND_CONF}"


    cat <<-EOL > "${rootfs}/etc/gdm3/custom.conf"
    # GDM configuration storage
    #
    # See /usr/share/gdm/gdm.schemas for a list of available options.

    [daemon]
    AutomaticLoginEnable=True
    AutomaticLogin=holomotion

    # Uncomment the line below to force the login screen to use Xorg
    # WaylandEnable=false

    # Enabling automatic login

    # Enabling timed login
    # TimedLoginEnable = true
    # TimedLogin = user1
    # TimedLoginDelay = 10

    [security]

    [xdmcp]

    [chooser]

    [debug]
    # Uncomment the line below to turn on debugging
    # More verbose logs
    # Additionally lets the X server dump core if it crashes
    #Enable=true
EOL

    # hdmi audio auto switch
    cp "${overlay}/usr/lib/scripts/hdmi_sound_toggle.sh" "${rootfs}/usr/lib/scripts/hdmi_sound_toggle.sh"
    chmod +x "${rootfs}/usr/lib/scripts/hdmi_sound_toggle.sh"
    cat <<-EOF >"${rootfs}/etc/udev/rules.d/99-hdmi_sound.rules"
    KERNEL=="card0", SUBSYSTEM=="drm", ACTION=="change", RUN+="/usr/lib/scripts/hdmi_sound_toggle.sh"
EOF

    # apply berxel usb rules
    cat <<-EOF >"${rootfs}/etc/udev/rules.d/berxel-usb.rules"
    SUBSYSTEM=="usb", ATTR{idProduct}=="8612", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="86ff", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0001", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="1001", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0002", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0003", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0004", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0003", ATTR{idVendor}=="04b4", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0005", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="1006", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0004", ATTR{idVendor}=="0c45", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0007", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0008", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0009", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000a", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000b", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000c", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000d", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000e", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000f", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
EOF


    echo "create build info in image"
    repo_owner="holomotion"
    repo_name="ubuntu-rockchip"

    build_release_id=$(curl -s "https://api.github.com/repos/$repo_owner/$repo_name/releases/latest" | jq -r .tag_name)
    build_commit_id=$(curl -s "https://api.github.com/repos/$repo_owner/$repo_name/commits" | jq -r '.[0].sha')
    build_time=$(date +"%Y-%m-%d %H:%M:%S")

    os_build_version="/etc/os_build_version"
    cat <<-EOF >"${rootfs}${os_build_version}"
    build:$build_release_id-$build_commit_id
    source:https://github.com/$repo_owner/$repo_name
    build time: $build_time
EOF
    chroot "${rootfs}"  chmod 644 "$os_build_version"
    chroot "${rootfs}"  cat "$os_build_version"

    echo "prepare os features dir"
    # setup os features
    chroot "${rootfs}"  mkdir -p /etc/features

    echo "run quick setup script completed"

    return 0
}
