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

# Check if the file exists and contains expected content
if [  -f "$RUSTDESK_CONFIG_FILE" ] && ! contains_expected_content "$EXPECTED_CONTENT" "$RUSTDESK_CONFIG_FILE"; then
    # Overwrite the file with the expected content
    echo "$EXPECTED_CONTENT" > "$RUSTDESK_CONFIG_FILE"
    systemctl restart rustdesk
    # set rustdesk password
    rustdesk --password "$RUSTDESK_PASSWORD"
    systemctl restart rustdesk
fi