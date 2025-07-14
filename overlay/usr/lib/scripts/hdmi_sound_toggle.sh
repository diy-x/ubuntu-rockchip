#!/bin/env bash

export LANG=en-US

USER_NAME=$(whoami)
USER_ID=$(id -u "$USER_NAME")
CARD_PATH="/sys/class/drm/card0/"
PULSE_SERVER="unix:/run/user/$USER_ID/pulse/native"

declare -A OUTPUT_MAP

hdmi_sinks_list=($(pactl list short sinks | grep -i 'HDMI' | awk '{print $2}' | sort -t'-' -k3,3n))

index=1
for hdmi in "${hdmi_sinks_list[@]}"; do
    OUTPUT_MAP["card0-HDMI-A-$index"]="$hdmi"
    ((index++))
done

AUDIO_OUTPUT="alsa_output.platform-es8388-sound.stereo-fallback"

for OUTPUT in $(cd "$CARD_PATH" && echo card*); do
  OUT_STATUS=$(<"$CARD_PATH"/"$OUTPUT"/status)
  if [[ $OUT_STATUS == connected ]]; then
    echo "$OUTPUT connected"
    if [[ -n "${OUTPUT_MAP[$OUTPUT]}" ]]; then
      AUDIO_OUTPUT="${OUTPUT_MAP[$OUTPUT]}"
    fi
  fi
done

echo "Selecting output $AUDIO_OUTPUT"

sudo -u "$USER_NAME" PULSE_SERVER="$PULSE_SERVER" pactl set-default-sink "$AUDIO_OUTPUT"