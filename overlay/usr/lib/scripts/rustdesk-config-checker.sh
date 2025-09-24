#!/bin/env bash
RUSTDESK_PASSWORD="Holo#Motion"
RUSTDESK_CONFIG_DIRS=("/root/.config/rustdesk" "/home/holomotion/.config/rustdesk")
RUSTDESK_CONFIG_FILES=("${RUSTDESK_CONFIG_DIRS[0]}/RustDesk2.toml" "${RUSTDESK_CONFIG_DIRS[1]}/RustDesk2.toml")

EXPECTED_CONTENT=$(cat <<EOF
rendezvous_server = 'rustdesk.ntsports.tech:21116'
nat_type = 1
serial = 0

[options]
access-mode = 'full'
direct-server = 'Y'
relay-server = 'rustdesk.ntsports.tech'
custom-rendezvous-server = 'rustdesk.ntsports.tech'
verification-method = 'use-permanent-password'
approve-mode = 'password'
default-connect-password = '${RUSTDESK_PASSWORD}'
hide-security-settings = 'Y'
EOF
)

# Function to check if file contains expected content
contains_expected_content() {
    local content="$1"
    local file="$2"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if ! grep -Fxq "$line" "$file" 2>/dev/null; then
            return 1
        fi
    done <<< "$content"
    return 0
}

# Function to wait for RustDesk service to be ready
wait_for_rustdesk() {
    echo "Waiting for RustDesk service to start..."
    local max_attempts=15
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet rustdesk; then
            echo "RustDesk service started, waiting 5 seconds to ensure full readiness..."
            sleep 5
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: RustDesk service not ready, waiting 3 seconds..."
        sleep 3
        ((attempt++))
    done
    echo "Warning: RustDesk service may not have started properly"
    return 1
}

# Function to create config for a specific user
create_user_config() {
    local config_dir="$1"
    local config_file="$2"
    local user_name="$3"
    
    echo "Processing config for user: $user_name (dir: $config_dir)"
    
    # Create config directory with proper ownership
    mkdir -p "$config_dir"
    
    # Set proper ownership for holomotion user directory
    if [[ "$user_name" == "holomotion" ]]; then
        if id "holomotion" &>/dev/null; then
            chown -R holomotion:holomotion "$config_dir"
            echo "Set ownership for holomotion user directory"
        else
            echo "Warning: holomotion user does not exist, skipping ownership change"
            return 1
        fi
    fi
    
    # Write config file
    echo "$EXPECTED_CONTENT" > "$config_file"
    chmod 600 "$config_file"
    
    # Set proper ownership for holomotion user config file
    if [[ "$user_name" == "holomotion" ]] && id "holomotion" &>/dev/null; then
        chown holomotion:holomotion "$config_file"
    fi
    
    echo "✓ Config created for $user_name: $config_file"
    return 0
}

# Check if any config needs update
config_needs_update=false
for i in "${!RUSTDESK_CONFIG_FILES[@]}"; do
    config_file="${RUSTDESK_CONFIG_FILES[$i]}"
    if [ ! -f "$config_file" ] || ! contains_expected_content "$EXPECTED_CONTENT" "$config_file"; then
        config_needs_update=true
        break
    fi
done

if [ "$config_needs_update" = true ]; then
    echo "Updating RustDesk configuration for all users..."
    
    # Create configs for all users
    user_names=("root" "holomotion")
    config_created=false
    
    for i in "${!RUSTDESK_CONFIG_DIRS[@]}"; do
        config_dir="${RUSTDESK_CONFIG_DIRS[$i]}"
        config_file="${RUSTDESK_CONFIG_FILES[$i]}"
        user_name="${user_names[$i]}"
        
        if create_user_config "$config_dir" "$config_file" "$user_name"; then
            config_created=true
        fi
    done
    
    if [ "$config_created" = true ]; then
        # Stop service completely
        echo "Stopping RustDesk service..."
        systemctl stop rustdesk 2>/dev/null || true
        sleep 2
        pkill -f rustdesk 2>/dev/null || true
        sleep 1
        
        # Start service
        echo "Starting RustDesk service..."
        systemctl start rustdesk
        
        # Wait for service to be fully ready
        if wait_for_rustdesk; then
            echo "Setting RustDesk password..."
            # Try multiple times with delay
            for i in {1..5}; do
                if rustdesk --password "$RUSTDESK_PASSWORD" 2>/dev/null; then
                    echo "✓ Password set successfully"
                    break
                else
                    echo "Attempt $i failed, waiting 3 seconds..."
                    sleep 3
                fi
            done
            
            # Final restart to ensure config takes effect
            echo "Final restart to ensure configuration takes effect..."
            systemctl restart rustdesk
            sleep 3
        else
            echo "Warning: Service startup abnormal, skipping password setting"
        fi
        
        echo "RustDesk configuration completed for all users"
    else
        echo "Warning: No configurations were successfully created"
    fi
else
    echo "RustDesk configuration is already up to date for all users"
fi

# Show final status
if systemctl is-active --quiet rustdesk; then
    echo "✓ RustDesk service is running normally"
    
    # Show config status for each user
    for i in "${!RUSTDESK_CONFIG_FILES[@]}"; do
        config_file="${RUSTDESK_CONFIG_FILES[$i]}"
        user_name="${user_names[$i]}"
        if [ -f "$config_file" ]; then
            echo "✓ Config exists for $user_name: $config_file"
        else
            echo "✗ Config missing for $user_name: $config_file"
        fi
    done
else
    echo "✗ RustDesk service is not running"
fi
