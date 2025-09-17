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

# Create config directory
mkdir -p "$RUSTDESK_CONFIG_DIR"

# Check if update is needed
if [ ! -f "$RUSTDESK_CONFIG_FILE" ] || ! contains_expected_content "$EXPECTED_CONTENT" "$RUSTDESK_CONFIG_FILE"; then
    echo "Updating RustDesk configuration..."
    
    # Write config file
    echo "$EXPECTED_CONTENT" > "$RUSTDESK_CONFIG_FILE"
    chmod 600 "$RUSTDESK_CONFIG_FILE"
    
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
