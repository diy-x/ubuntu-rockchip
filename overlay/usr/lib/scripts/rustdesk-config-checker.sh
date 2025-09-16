#!/bin/env bash
RUSTDESK_PASSWORD="Holo#Motion"
RUSTDESK_CONFIG_DIR="/root/.config/rustdesk"
RUSTDESK_CONFIG_FILE="${RUSTDESK_CONFIG_DIR}/RustDesk2.toml"
EXPECTED_CONTENT=$(cat <<EOF
rendezvous_server = 'rustdesk.ntsports.tech:21116'
nat_type = 1
serial = 0
[options]
access-mode = 'full'
direct-server = 'Y'
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
        if ! grep -Fxq "$line" "$file"; then
            return 1
        fi
    done <<< "$content"
    return 0
}

# Function to wait for RustDesk service to be ready
wait_for_rustdesk() {
    echo "Waiting for RustDesk service to start..."
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Check if service is running
        if systemctl is-active --quiet rustdesk; then
            echo "RustDesk service started, waiting 2 seconds to ensure readiness..."
            sleep 2
            return 0
        fi
        
        echo "Attempt $attempt/$max_attempts: RustDesk service not ready, waiting 2 seconds..."
        sleep 2
        ((attempt++))
    done
    
    echo "Warning: RustDesk service may not have started properly"
    return 1
}

# Create config directory
mkdir -p "$RUSTDESK_CONFIG_DIR"

# Fix logic: check if file doesn't exist or content doesn't match
if [ ! -f "$RUSTDESK_CONFIG_FILE" ] || ! contains_expected_content "$EXPECTED_CONTENT" "$RUSTDESK_CONFIG_FILE"; then
    echo "Updating RustDesk configuration..."
    
    # Write config file
    echo "$EXPECTED_CONTENT" > "$RUSTDESK_CONFIG_FILE"
    
    # Restart service and wait for readiness
    echo "Restarting RustDesk service..."
    systemctl restart rustdesk
    
    # Wait for service to fully start
    if wait_for_rustdesk; then
        echo "Setting RustDesk password..."
        # Try to set password, capture error output
        if rustdesk --password "$RUSTDESK_PASSWORD" 2>&1; then
            echo "✓ Password set successfully via command line"
        else
            echo "⚠ Command line password setting failed, but password is set in config file and should still work"
        fi
        
        # Restart service again to ensure config takes effect
        echo "Restarting service to ensure configuration takes effect..."
        systemctl restart rustdesk
    else
        echo "Warning: Service startup abnormal, skipping password setting"
    fi
    
    echo "RustDesk configuration completed"
else
    echo "RustDesk configuration is already up to date"
fi

# Show final status
if systemctl is-active --quiet rustdesk; then
    echo "✓ RustDesk service is running normally"
else
    echo "✗ RustDesk service is not running"
fi
