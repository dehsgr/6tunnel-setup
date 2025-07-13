#!/bin/bash
# 6tunnel-setup.sh
# Version: 1.0.0

VERSION="1.0.0"
CONFIG_FILE="/etc/6tunnel-setup.conf"
BACKUP_FILE="/etc/6tunnel-setup.conf.bak"
SYSTEMD_UNIT="/etc/systemd/system/6tunnel-setup.service"

set -e

function cleanup {
    tput sgr0   # reset terminal colors
    clear
}
trap cleanup EXIT

function check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root."
        exit 1
    fi
}

function check_dialog() {
    if ! command -v dialog >/dev/null 2>&1; then
        read -rp "'dialog' is not installed. Install it now? [Y/n] " yn
        yn=${yn:-Y}
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            apt-get update && apt-get install -y dialog
        else
            echo "Cannot proceed without 'dialog'. Exiting."
            exit 1
        fi
    fi
}

function check_6tunnel() {
    if ! command -v 6tunnel >/dev/null 2>&1; then
        read -rp "'6tunnel' is not installed. Install it now? [Y/n] " yn
        yn=${yn:-Y}
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            apt-get update && apt-get install -y 6tunnel
        else
            echo "Cannot proceed without '6tunnel'. Exiting."
            exit 1
        fi
    fi
}

function show_about() {
    dialog --title "About" --msgbox "6tunnel-setup\nVersion: $VERSION\nAuthor: dehsgr\nLicense: ISC" 10 50
}

function backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
    fi
}

function create_systemd_service() {
    cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=6tunnel Setup Service
After=network.target

[Service]
ExecStart=/bin/bash -c '/usr/bin/awk "{print \"/usr/bin/6tunnel \" \$1 \" \" \$2 \" \" \$3}"' "$CONFIG_FILE" | /bin/bash
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
}

function install() {
    backup_config
    local entries=""
    while true; do
        local result=$(dialog --stdout --title "New Tunnel" \
            --form "Enter tunnel configuration (leave empty Source port to finish):" 15 50 3 \
            "Source port:" 1 1 "" 1 20 5 0 \
            "Target address:" 2 1 "" 2 20 30 0 \
            "Target port:" 3 1 "" 3 20 5 0)
        if [ -z "$result" ]; then
            break
        fi
        local src=$(echo "$result" | sed -n 1p)
        if [ -z "$src" ]; then
            break
        fi
        local tgt_addr=$(echo "$result" | sed -n 2p)
        local tgt_port=$(echo "$result" | sed -n 3p)
        entries+="$src $tgt_addr $tgt_port\n"
    done
    if [ -n "$entries" ]; then
        echo -e "$entries" > "$CONFIG_FILE"
        create_systemd_service
        systemctl daemon-reload
        systemctl enable --now 6tunnel-setup.service
        dialog --msgbox "Installation complete and service started." 6 40
    else
        dialog --msgbox "No tunnels configured." 6 40
    fi
}

function modify() {
    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --msgbox "No configuration found." 6 40
        return
    fi

    backup_config

    while true; do
        # Build menu options: line numbers + current config for easy selection
        local options=()
        local i=1
        while read -r src tgt_addr tgt_port; do
            options+=("$i" "$src → $tgt_addr:$tgt_port")
            ((i++))
        done < "$CONFIG_FILE"
        options+=("0" "Done")

        choice=$(dialog --stdout --menu "Select tunnel to edit or delete:" 20 60 10 "${options[@]}")

        if [[ "$choice" == "0" || -z "$choice" ]]; then
            # Exit modify menu
            break
        fi

        # Get selected line content
        line_content=$(sed -n "${choice}p" "$CONFIG_FILE")
        src=$(echo "$line_content" | awk '{print $1}')
        tgt_addr=$(echo "$line_content" | awk '{print $2}')
        tgt_port=$(echo "$line_content" | awk '{print $3}')

        # Ask edit or delete
        action=$(dialog --stdout --menu "Edit or delete the tunnel?\n$src → $tgt_addr:$tgt_port" 10 40 2 1 Edit 2 Delete)

        if [[ "$action" == "1" ]]; then
            # Edit
            new_result=$(dialog --stdout --form "Edit tunnel configuration:" 15 50 3 \
                "Source port:" 1 1 "$src" 1 20 5 0 \
                "Target address:" 2 1 "$tgt_addr" 2 20 30 0 \
                "Target port:" 3 1 "$tgt_port" 3 20 5 0)

            if [ -z "$new_result" ]; then
                dialog --msgbox "Edit cancelled, entry unchanged." 6 40
                continue
            fi

            new_src=$(echo "$new_result" | sed -n 1p)
            new_tgt_addr=$(echo "$new_result" | sed -n 2p)
            new_tgt_port=$(echo "$new_result" | sed -n 3p)

            # Replace line in config
            sed -i "${choice}s/.*/$new_src $new_tgt_addr $new_tgt_port/" "$CONFIG_FILE"
            systemctl restart 6tunnel-setup.service
            dialog --msgbox "Entry updated and service restarted." 6 50

        elif [[ "$action" == "2" ]]; then
            # Delete
            sed -i "${choice}d" "$CONFIG_FILE"
            systemctl restart 6tunnel-setup.service
            dialog --msgbox "Entry deleted and service restarted." 6 50
        fi
    done
}

function uninstall() {
    systemctl disable --now 6tunnel-setup.service || true
    rm -f "$SYSTEMD_UNIT" "$CONFIG_FILE"
    systemctl daemon-reload
    read -rp "Also remove dependencies ('6tunnel', 'dialog')? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        apt-get remove -y 6tunnel dialog
    fi
    dialog --msgbox "Uninstallation complete." 6 40
}

function main_menu() {
    while true; do
        choice=$(dialog --clear --stdout --title "6tunnel-setup v$VERSION" \
            --menu "Choose an option:" 15 50 5 \
            1 "Install" \
            2 "Modify configuration" \
            3 "Uninstall" \
            4 "About" \
            5 "Exit")
        case "$choice" in
            1) install ;;
            2) modify ;;
            3) uninstall ;;
            4) show_about ;;
            5) clear; exit ;;
            *) clear; exit ;;
        esac
    done
}

check_root
check_dialog
check_6tunnel
main_menu