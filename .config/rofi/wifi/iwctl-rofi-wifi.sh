#!/usr/bin/env bash

# iwctl + rofi Wi-Fi menu
# Requirements: iwd (iwctl), rofi, (optional) libnotify/notify-send

# Change this to your Wi-Fi interface (check via: ip link | grep wl)
INTERFACE="${1:-wlan0}"

ROFI_CMD='rofi -dmenu -p Wi-Fi -i -theme ~/.config/rofi/themes/wifi-catppuccin.rasi'

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Wi-Fi" "$1"
  fi
}

# Convert signal field (e.g. ***** or 70) to bar icons
signal_to_bars() {
  local sig="$1"

  # If it's stars like *, ***, *****
  if [[ "$sig" =~ ^\*+$ ]]; then
    local n=${#sig}
    case $n in
    1) echo "▂" ;;
    2) echo "▂▄" ;;
    3) echo "▂▄▆" ;;
    4) echo "▂▄▆█" ;;
    *) echo "▂▄▆█" ;;
    esac
    return
  fi

  # If it's numeric (0–100)
  if [[ "$sig" =~ ^[0-9]+$ ]]; then
    local val="$sig"
    if ((val < 25)); then
      echo "▂"
    elif ((val < 50)); then
      echo "▂▄"
    elif ((val < 75)); then
      echo "▂▄▆"
    else
      echo "▂▄▆█"
    fi
    return
  fi

  # Fallback
  echo "▂▄▆█"
}

scan_networks() {
  iwctl station "$INTERFACE" scan >/dev/null 2>&1
  sleep 1
}

# Parse iwctl get-networks into: "SSID  🔒  ▂▄▆█"
get_networks() {
  iwctl station "$INTERFACE" get-networks 2>/dev/null |
    sed '1,4d' |
    sed '/^\s*$/d' |
    sed 's/^[* ]*//' |
    while read -r line; do
      # Example line: MyWiFi       psk   *****
      # Split into fields: name security signal
      ssid=$(echo "$line" | awk '{print $1}')
      sec=$(echo "$line" | awk '{print $2}')
      sig=$(echo "$line" | awk '{print $3}')

      # Lock / open icon
      if [[ "$sec" == "open" ]]; then
        lock_icon="🔓"
      else
        lock_icon="🔒"
      fi

      bars="$(signal_to_bars "$sig")"

      # Final menu line: "SSID  🔒  ▂▄▆█"
      printf "%s  %s  %s\n" "$ssid" "$lock_icon" "$bars"
    done | sort -u
}

connect_network() {
  local ssid="$1"
  local is_open="$2"

  if [[ "$is_open" == "yes" ]]; then
    # Open network: no password
    iwctl station "$INTERFACE" connect "$ssid"
  else
    # Ask for password; allow empty to try saved config
    PASS=$(echo "" | $ROFI_CMD -p "Password for $ssid" -password)

    if [[ -z "$PASS" ]]; then
      # Try without passphrase (saved network or open)
      iwctl station "$INTERFACE" connect "$ssid"
    else
      iwctl --passphrase "$PASS" station "$INTERFACE" connect "$ssid"
    fi
  fi

  if [[ $? -eq 0 ]]; then
    notify "Connected to $ssid"
  else
    notify "Failed to connect to $ssid"
  fi
}

disconnect_network() {
  iwctl station "$INTERFACE" disconnect
  notify "Disconnected"
}

main_menu() {
  # Removed scan_networks here for faster open

  CURRENT="$(iwctl station "$INTERFACE" show 2>/dev/null | awk '/Connected network/ {print $3}')"
  NETS="$(get_networks)"

  MENU=""
  if [[ -n "$CURRENT" ]]; then
    MENU+="  Connected: $CURRENT\n"
    MENU+="  Disconnect\n"
    MENU+="──────────────\n"
  fi

  MENU+="$NETS\n"
  MENU+="🔄  Rescan\n"

  CHOICE=$(echo -e "$MENU" | $ROFI_CMD)

  case "$CHOICE" in
  "  Disconnect")
    disconnect_network
    ;;
  "🔄  Rescan")
    scan_networks
    main_menu
    ;;
  "")
    # Esc / cancel
    exit 0
    ;;
  *)
    # Clicked on status line, ignore
    exit 0
    ;;
  *)
    # A network line like: "SSID  🔒  ▂▄▆█"
    # Extract SSID (before first double-space)
    SSID="${CHOICE%%  *}"

    # Decide if open or secured based on icon
    if [[ "$CHOICE" == *"🔓"* ]]; then
      IS_OPEN="yes"
    else
      IS_OPEN="no"
    fi

    connect_network "$SSID" "$IS_OPEN"
    ;;
  esac
}

main_menu
