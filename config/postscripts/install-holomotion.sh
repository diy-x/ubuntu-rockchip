#!/bin/bash

# shellcheck shell=bash
function install_holomotion() {
    local rootfs="$1"
    local overlay="$2"  # overlay 参数保留，即使在这个脚本中可能未使用
    echo "pre-install holomotion with rootfs:${rootfs} overlay:${overlay}"

    installerRepo="https://e.coding.net/g-hvab4800/holomotion_update/HoloMotion_Update.git"
    VERSION_REGEX_RELEASE="^[0-9]+\.[0-9]+\.[0-9]+-[0-9]{8}$"

    install_dir="/home/holomotion/local/bin" # 用户空间内的安装目录
    ntsport_dir="$install_dir/ntsports"
    program_dir="$ntsport_dir/HoloMotion"

    startup_bin="$install_dir/HoloMotion"
    startup_png="$program_dir/assets/watermark_logo.png"

    startup_app="$program_dir/NT.Client.sh"
    startup_app_src="$program_dir/NT.Client"

    install_bin="$install_dir/HoloMotion" # 与 startup_bin 相同, 保留以兼容
    install_app="$ntsport_dir/HoloMotion_Update_installer.sh"
    install_src="$program_dir/HoloMotion_Update_installer.sh"

    # 1. 创建目录（在 chroot 环境中）
    chroot "${rootfs}" /bin/bash -c "[ -d $ntsport_dir ] || mkdir -p $ntsport_dir"

    # 2. 写入 branch.txt (固定为 release, 与你第一个脚本一致)
    cat <<-EOF >"${rootfs}${ntsport_dir}/branch.txt"
    release
EOF

    # 3. 克隆仓库（在 chroot 环境中）
    chroot "${rootfs}" git clone "$installerRepo" "$program_dir"
    chroot "${rootfs}" git config --global --add safe.directory "$program_dir"
    chroot "${rootfs}" /bin/bash -c "sudo -u holomotion git config --global --add safe.directory '${program_dir}'"


    # 4. 获取并切换到最新 release 版本（在 chroot 环境中）
    latest_version=$(chroot "${rootfs}" /bin/bash -c "git -C $program_dir ls-remote --tags --refs origin | awk -F/ '{print \$3}' | grep -E '$VERSION_REGEX_RELEASE' | sort -t '-' -k 1,1V -k 2,2n | awk 'END{print}'")
    if echo "$latest_version" | grep -qE "$VERSION_REGEX_RELEASE"; then
        echo "got latest release version $latest_version"
        chroot "${rootfs}" git -C "$program_dir" reset --hard "$latest_version"
    fi

    # 5. 复制安装脚本并创建软链接（在 chroot 环境中）
    if [ -f "${rootfs}${install_src}" ]; then
        echo "copying ${install_src} to ${install_app} in ${rootfs}"
        chroot "${rootfs}" cp -f "${install_src}" "${install_app}" >/dev/null 2>&1 || true
        echo "create soft link for $install_app  with target $install_bin"
        chroot "${rootfs}" ln -s -f "$install_app" "$install_bin" >/dev/null 2>&1 || true
        chroot "${rootfs}" chmod +x "$install_app" >/dev/null 2>&1 || true
    fi

    # 6. 创建启动脚本的软链接（在 chroot 环境中）
    if [ -f "${rootfs}${startup_app}" ]; then
        echo "create soft link for $startup_app  with target $startup_bin"
        chroot "${rootfs}" ln -s -f "$startup_app" "$startup_bin" >/dev/null 2>&1 || true
        chroot "${rootfs}" chmod +x "$startup_app" >/dev/null 2>&1 || true
        chroot "${rootfs}" chmod +x "$startup_app_src" >/dev/null 2>&1 || true
    fi

    # 7. 创建桌面文件 (在 chroot环境中)
    mkdir -p "${rootfs}/usr/share/applications"
    cat <<-EOF >"${rootfs}/usr/share/applications/HoloMotion.desktop"
    [Desktop Entry]
    Type=Application
    Name=HoloMotion
    GenericName=HoloMotion
    Comment=HoloMotion
    Exec=$startup_app
    Icon=$startup_png
    Terminal=true
    Categories=X-Application;
EOF

    # 8. 创建自启动文件 (在chroot环境中)
    mkdir -p "${rootfs}/home/holomotion/.config/autostart"
    cat <<-EOF >"${rootfs}/home/holomotion/.config/autostart/HoloMotion.desktop"
    [Desktop Entry]
    Type=Application
    Name=HoloMotion
    GenericName=HoloMotion
    Comment=HoloMotion
    Exec=$startup_app
    Icon=$startup_png
    Terminal=true
    Categories=X-Application;
EOF

    # 9. 设置 holomotion 用户的所有权（在 chroot 环境中）
    chroot "${rootfs}" /bin/bash -c "chown -R holomotion:holomotion /home/holomotion"

    echo "pre-install holomotion completed"
    return 0
}
# 保持你第一个脚本的调用方式
if [ "$#" -ge 1 ]; then
    install_holomotion "$@"  #直接传递所有参数
fi
