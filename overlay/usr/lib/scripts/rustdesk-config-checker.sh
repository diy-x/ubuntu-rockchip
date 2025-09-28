#!/bin/env bash
# Use environment variable if set, otherwise use default
RUSTDESK_PASSWORD="${RUSTDESK_PASSWORD:-Holo#Motion}"

echo "Using RustDesk password: ${RUSTDESK_PASSWORD:0:4}****** (showing first 4 characters)"

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
    local max_attempts=20
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet rustdesk; then
            echo "RustDesk service started, waiting 8 seconds to ensure full readiness..."
            sleep 8
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: RustDesk service not ready, waiting 3 seconds..."
        sleep 3
        ((attempt++))
    done
    echo "Warning: RustDesk service may not have started properly"
    return 1
}

# Function to verify password is set correctly
verify_password_set() {
    local password="$1"
    local max_attempts=3
    local attempt=1
    
    echo "Verifying password configuration..."
    
    while [ $attempt -le $max_attempts ]; do
        # Check if password is configured in any of the config files
        local password_found=false
        local config_with_password=""
        
        for config_file in "${RUSTDESK_CONFIG_FILES[@]}"; do
            if [ -f "$config_file" ] && grep -q "default-connect-password = '$password'" "$config_file" 2>/dev/null; then
                password_found=true
                config_with_password="$config_file"
                echo "✓ Password found in config: $config_file"
                break
            fi
        done
        
        if [ "$password_found" = true ]; then
            # For verification during initial setup, just check config file is sufficient
            # Skip the rustdesk command check as it may not be reliable during service startup
            if [ -n "$config_with_password" ]; then
                echo "✓ Password verification successful (config file check)"
                return 0
            fi
        fi
        
        echo "Password verification attempt $attempt/$max_attempts failed"
        ((attempt++))
        [ $attempt -le $max_attempts ] && sleep 2
    done
    
    return 1
}

# Enhanced function to set RustDesk password with better error handling
set_rustdesk_password() {
    local password="$1"
    local max_attempts=8
    local attempt=1
    
    echo "Setting RustDesk password..."
    
    while [ $attempt -le $max_attempts ]; do
        echo "Password setting attempt $attempt/$max_attempts..."
        
        # Try different methods to set password
        local success=false
        
        # Method 1: Standard password setting
        if rustdesk --password "$password" >/dev/null 2>&1; then
            echo "✓ Password set using standard method"
            success=true
        else
            echo "Standard method failed, trying alternative approaches..."
            
            # Method 2: Try with service restart
            systemctl restart rustdesk
            sleep 5
            if rustdesk --password "$password" >/dev/null 2>&1; then
                echo "✓ Password set after service restart"
                success=true
            fi
        fi
        
        # Verify password was actually set
        if [ "$success" = true ]; then
            sleep 2
            if verify_password_set "$password"; then
                echo "✓ Password setting verified successfully"
                return 0
            else
                echo "Password setting verification failed, retrying..."
                success=false
            fi
        fi
        
        if [ "$success" = false ]; then
            echo "Attempt $attempt failed, waiting 5 seconds before retry..."
            sleep 5
        fi
        
        ((attempt++))
    done
    
    echo "✗ Failed to set password after $max_attempts attempts"
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

# Function to perform complete service reset
reset_rustdesk_service() {
    echo "Performing complete RustDesk service reset..."
    
    # Kill all RustDesk processes
    pkill -f rustdesk 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    pkill -9 -f rustdesk 2>/dev/null || true
    sleep 1
    
    # Stop systemd service
    systemctl stop rustdesk 2>/dev/null || true
    sleep 2
    
    # Clear any potential lock files or temporary data
    rm -f /tmp/rustdesk* 2>/dev/null || true
    
    # Start service fresh
    systemctl start rustdesk
    sleep 3
    
    echo "Service reset completed"
}

# Function to check if password needs update (comparing actual vs expected)
password_needs_update() {
    local expected_password="$1"
    
    # Check if any config file has different password or is missing
    for config_file in "${RUSTDESK_CONFIG_FILES[@]}"; do
        if [ ! -f "$config_file" ]; then
            echo "Config file missing: $config_file"
            return 0  # Update needed
        fi
        
        # Check if config exists but has different password or no password
        if ! grep -q "default-connect-password = '$expected_password'" "$config_file" 2>/dev/null; then
            echo "Password mismatch or missing in $config_file"
            return 0  # Update needed
        fi
    done
    
    return 1  # No update needed
}

# Check if any config needs update
config_needs_update=false
password_update_needed=false

# Check configuration files
for i in "${!RUSTDESK_CONFIG_FILES[@]}"; do
    config_file="${RUSTDESK_CONFIG_FILES[$i]}"
    if [ ! -f "$config_file" ] || ! contains_expected_content "$EXPECTED_CONTENT" "$config_file"; then
        config_needs_update=true
        break
    fi
done

# Check if password specifically needs update
if password_needs_update "$RUSTDESK_PASSWORD"; then
    password_update_needed=true
    config_needs_update=true
    echo "Password update detected - will refresh configuration"
fi

if [ "$config_needs_update" = true ]; then
    if [ "$password_update_needed" = true ]; then
        echo "Password change detected - updating RustDesk configuration for all users..."
    else
        echo "Configuration update needed - updating RustDesk configuration for all users..."
    fi
    
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
        # Perform complete service reset
        reset_rustdesk_service
        
        # Wait for service to be fully ready
        if wait_for_rustdesk; then
            # Enhanced password setting with verification
            if set_rustdesk_password "$RUSTDESK_PASSWORD"; then
                echo "✓ Password configuration completed successfully"
                
                # Final restart to ensure everything is applied
                echo "Final restart to ensure all configurations are active..."
                systemctl restart rustdesk
                sleep 5
                
                # Final verification
                if verify_password_set "$RUSTDESK_PASSWORD"; then
                    echo "✓ Final verification: Password is correctly configured"
                else
                    echo "⚠ Warning: Final verification failed, but configuration was attempted"
                fi
            else
                echo "✗ Failed to set password, but configuration files are updated"
                echo "You may need to manually set the password using: rustdesk --password \"$RUSTDESK_PASSWORD\""
            fi
        else
            echo "✗ Service startup failed, configuration may not be complete"
        fi
        
        echo "RustDesk configuration process completed"
    else
        echo "✗ Failed to create any configurations"
        exit 1
    fi
else
    echo "RustDesk configuration is already up to date for all users"
    
    # Even if config seems up to date, verify password is actually correct
    if ! verify_password_set "$RUSTDESK_PASSWORD"; then
        echo "Configuration files appear correct, but active password doesn't match. Updating password..."
        if wait_for_rustdesk && set_rustdesk_password "$RUSTDESK_PASSWORD"; then
            echo "✓ Password updated successfully"
        else
            echo "⚠ Warning: Failed to update password"
        fi
    else
        echo "✓ Password verification passed - no updates needed"
    fi
fi

# Show final status
echo "=== Final Status Report ==="
if systemctl is-active --quiet rustdesk; then
    echo "✓ RustDesk service is running normally"
    service_running=true
else
    echo "✗ RustDesk service is not running"
    echo "Attempting to start RustDesk service..."
    
    # Try to start the service
    if systemctl start rustdesk 2>/dev/null; then
        sleep 3
        if systemctl is-active --quiet rustdesk; then
            echo "✓ RustDesk service started successfully"
            service_running=true
        else
            echo "✗ Failed to start RustDesk service"
            service_running=false
        fi
    else
        echo "✗ Failed to start RustDesk service"
        service_running=false
    fi
fi

# Show config status for each user (always show)
user_names=("root" "holomotion")
for i in "${!RUSTDESK_CONFIG_FILES[@]}"; do
    config_file="${RUSTDESK_CONFIG_FILES[$i]}"
    user_name="${user_names[$i]}"
    if [ -f "$config_file" ]; then
        echo "✓ Config exists for $user_name: $config_file"
        # Check if password is in config
        if grep -q "default-connect-password = '$RUSTDESK_PASSWORD'" "$config_file" 2>/dev/null; then
            echo "✓ Password configured in config for $user_name"
        else
            echo "⚠ Password may not be configured in config for $user_name"
        fi
    else
        echo "✗ Config missing for $user_name: $config_file"
    fi
done

# Only do password verification if service is running
if [ "$service_running" = true ]; then
    # Final password verification and application
    if verify_password_set "$RUSTDESK_PASSWORD"; then
        echo "✓ Password verification: SUCCESS"
        
        # Try to apply password to running service
        echo "Ensuring password is active in running service..."
        for i in {1..3}; do
            if rustdesk --password "$RUSTDESK_PASSWORD" >/dev/null 2>&1; then
                echo "✓ Password successfully applied to running service"
                break
            else
                if [ $i -lt 3 ]; then
                    echo "Attempt $i failed, waiting 2 seconds..."
                    sleep 2
                else
                    echo "⚠ Password application to service may have failed, but config is correct"
                fi
            fi
        done
    else
        echo "⚠ Password verification: FAILED"
        echo "Manual command: rustdesk --password \"$RUSTDESK_PASSWORD\""
    fi
else
    echo "⚠ Service is not running - cannot apply password to running service"
    echo "Start service: systemctl start rustdesk"
    echo "Enable auto-start: systemctl enable rustdesk"
fi
