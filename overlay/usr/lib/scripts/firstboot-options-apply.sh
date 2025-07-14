#!/bin/env bash

exec &> /var/log/firstboot-options-apply.log

target_user="holomotion"
default_desktop_dir="/home/holomotion/桌面"

feature_custom_wifi="/etc/features/enable_custom_wifi"


get_wireless_interfce() {
	local interface=$(iwconfig 2>/dev/null | awk '/^[a-zA-Z0-9]+/ { print $1; exit }')
	if [ -n "$interface" ]; then
		echo "$interface"
	else
		echo "No wireless interface found" >&2
		return 1
	fi
}


is_masked() {
    systemctl status "$1" 2>&1 | grep -q 'masked'
}

enable_custom_wifi() {
	# 获取无线接口名
	# shellcheck disable=SC2155
	local interface=$(get_wireless_interfce)
	if [ $? -ne 0 ]; then
		echo "No wireless interface found."
		return 1
	fi

	# 配置 systemd-network 
	echo "Configuring systemd-network for interface $interface..."
    cat <<-EOL > /etc/systemd/network/10-${interface}.network 
    [Match]
    Name=${interface}

    [Network]
    DHCP=yes
EOL

	echo "systemd-network configuration completed."

	local max_retries=10
	local retry_interval=2

	# 检查 NetworkManager 是否已禁用
	for ((i=1; i<=max_retries; i++)); do	
		if systemctl is-enabled NetworkManager &> /dev/null; then
			echo "Disabling NetworkManager..."
			systemctl disable NetworkManger
			sleep $retry_interval
		else 
			echo "NetworkManager is already disabled."
			break;
		fi
	done

	# 检查 NetworkManager 是否已停用
	for ((i=1; i<=max_retries; i++)); do
		if systemctl is-active NetworkManager &> /dev/null; then
			echo "Stopping NetworkManager..."
			systemctl stop NetworkManager
			#systemctl daemon-reload
			sleep $retry_interval
		else
			echo "NetworkManager is already stopped."
			break;
		fi
	done
	# 永远禁止 NetworkManager 运行
	for ((i=1; i<=max_retries; i++)); do
		if ! is_masked NetworkManager; then
			echo "Masking NetworkManager..."
			systemctl mask NetworkManager
			sleep $retry_interval
		else
			echo "NetworkManager is already masked."
			break
		fi
	done

	# 检查 systemd-networkd 是否已启用
	for ((i=1; i<=max_retries; i++)); do
		if systemctl is-enabled systemd-networkd &> /dev/null; then
			echo "systemd-networkd is already enabled."
			break
		else
			echo "Starting systemd-networkd..."
			systemctl enable systemd-networkd
			sleep $retry_interval
		fi
	done
	# 检查 systemd-networkd 是否已启动
	for ((i=1; i<=max_retries; i++)); do
		if systemctl is-active systemd-networkd &> /dev/null; then
			echo "systemd-networkd is already active."
			sleep 5
			# 重新启动 systemct-networkd
			systemctl restart systemd-networkd
			break
		else 
			echo "Starting systemd-networkd..."
			sudo systemctl start systemd-networkd
			sleep $retry_interval
		fi
	done

	# 检查 wpa_supplicant 是否启用
	for ((i=1; i<=max_retries; i++)); do
		if systemctl is-enabled wpa_supplicant &> /dev/null; then
			echo "wpa_supplicant is already enabled."
			break
		else 
			echo "Enabling wpa_supplicant"	
			systemctl enable wpa_supplicant
			sleep $retry_interval
		fi
	done

	# 检查 wpa_supplicant 是否已启动
	for ((i=1; i<=max_retries; i++)); do
		if systemctl is-active wpa_supplicant &> /dev/null; then
			echo "wpa_supplicant is already active."
			break
		else
			echo "Starting wpa_Supplicant..."
			systemctl start wpa_supplicant
			sleep $retry_interval
		fi
	done

}

# Function to get the D-Bus session address for a specific user
get_dbus_session_address() {
    local user=$1
    # shellcheck disable=SC2155
    local user_id=$(id -u "$user")
    local dbus_address_file="/run/user/$user_id/dbus-session"

    # If the D-Bus address file exists, read the address from it
    if [ -f "$dbus_address_file" ]; then
        # shellcheck disable=SC2155
        export DBUS_SESSION_BUS_ADDRESS=$(cat "$dbus_address_file")
    else
        # Otherwise, start a new D-Bus session for the user and save the address
        # shellcheck disable=SC2046
        eval $(sudo -u "$user" dbus-launch --sh-syntax)
        echo "$DBUS_SESSION_BUS_ADDRESS" > "$dbus_address_file"
    fi
}

# fix mpp service error
user_groups="adm cdrom dip video plugdev users lpadmin"
for ug in $user_groups;
do
    if id -nG $target_user | grep -qw "$ug"; then
        echo "user:$target_user already in $ug group."
    else
        echo "add user:$target_user to $ug group."
        usermod -aG "$ug" $target_user
    fi
done

# Get the D-Bus session address for the target user
get_dbus_session_address $target_user

echo "apply power options"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.session idle-delay 0
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.screensaver lock-enabled false


echo "adjust ibus ime"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.freedesktop.ibus.general engines-order "[ 'pinyin','xkb:us::eng']"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.freedesktop.ibus.general preload-engines "['pinyin']"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('ibus', 'libpinyin'), ('ibus', 'pinyin')]"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.input-sources current 2
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" ibus restart

gnome-extensions disable tiling-assistant@ubuntu.com
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.mutter edge-tiling false

if [ -f "/usr/share/shellextensions/disable-gestures-three-fingers.shell-extension.zip" ];then
	sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"  gnome-extensions install "/usr/share/shellextensions/disable-gestures-three-fingers.shell-extension.zip"
    shell_extension_name="disable-gestures-three-above@holomotion.tech"
    if sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gnome-extensions list | grep -q $shell_extension_name; then
		echo "pre-enable shell extension:disable-gestures-three-fingers"
		sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"   gnome-extensions enable $shell_extension_name
    fi
fi

if [ -f "/usr/share/backgrounds/holomotion_h.png" ];then
    echo "set wallpaper"
    sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/holomotion_h.png'
fi

echo "fix desktop files"

user_desktop_dir=$(sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" xdg-user-dir DESKTOP || echo "$default_desktop_dir")


echo "enable keyboard"
sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true

holomotion_desktop_file="/usr/share/applications/HoloMotion.desktop"
if [ -f $holomotion_desktop_file ]; then
    echo "create Holomotion desktop file.."
    cp -f $holomotion_desktop_file "$user_desktop_dir"
    chown $target_user:$target_user "$user_desktop_dir/HoloMotion.desktop"
    chmod a+x "$user_desktop_dir/HoloMotion.desktop"
    sudo -u holomotion env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gio set "$user_desktop_dir/HoloMotion.desktop" "metadata::trusted" true
fi

training_assist_desktop_file="/usr/share/applications/train_assist_client.desktop"
if [ -f $training_assist_desktop_file ]; then
    echo "create training assist desktop file.."
    cp -f $training_assist_desktop_file "$user_desktop_dir"
    chown $target_user:$target_user "$user_desktop_dir/train_assist_client.desktop"
    chmod a+x "$user_desktop_dir/train_assist_client.desktop"
    sudo -u holomotion env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gio set "$user_desktop_dir/train_assist_client.desktop" "metadata::trusted" true
fi

nt_tool_desktop_file="/usr/share/applications/NT.Tool.desktop"
if [ -f $nt_tool_desktop_file ]; then
    echo "create NT.Tool desktop file.."
    cp -f $nt_tool_desktop_file "$user_desktop_dir"
	chown $target_user:$target_user "$user_desktop_dir/NT.Tool.desktop"
    chmod a+x "$user_desktop_dir/NT.Tool.desktop"
    sudo -u holomotion env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gio set "$user_desktop_dir/NT.Tool.desktop" "metadata::trusted" true
fi


holomotion_autostart_file="/home/$target_user/.config/autostart/HoloMotion.desktop"
train_assist_autostart_file="/home/$target_user/.config/autostart/train_assist_client.desktop"
echo "check auto start file both exist.."

# if [ -f  $holomotion_desktop_file ];then
#     echo "adjust dock positions to better experience..."
# 	sudo -u $target_user env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" gsettings set org.gnome.shell.extensions.dash-to-dock dock-position BOTTOM
# fi

if  [ -f $holomotion_desktop_file ] && ! [ -f $holomotion_autostart_file ];then
	echo "add holomotion autostart"
	cp -f $holomotion_desktop_file $holomotion_autostart_file
fi

if [ -f $training_assist_desktop_file ] && ! [ -f $train_assist_autostart_file ];then
	echo "add training assist autostart"
	cp -f $training_assist_desktop_file $train_assist_autostart_file
fi

if [ -f $holomotion_autostart_file ] && [ -f $train_assist_autostart_file ];then
	echo "disable autostart when holomotion and  training assist installed both"
	rm -rf $holomotion_autostart_file
	rm -rf $train_assist_autostart_file
fi

echo "disable keyring service"
echo ""|gnome-keyring-daemon --replace --unlock
systemctl --user disable gnome-keyring-daemon.service

count_file="/home/$target_user/.config/firstboot-run-counter"
if [ ! -f "$count_file" ]; then
    echo 0 > "$count_file"
fi
count=$(cat "$count_file")
count=$((count + 1))
if [ $count -ge 6 ];then
    systemctl disable firstboot-options-apply
    rm -rf "$count_file"
fi
echo $count > "$count_file"

echo "check if need to apply features"
if [ -f $feature_custom_wifi ];then
	echo "setup custom wifi"
	enable_custom_wifi
fi