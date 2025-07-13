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
        timestamp=$(date +"%Y%m%d_%H%M%S")
        cp "$CONFIG_FILE" "${BACKUP_FILE}.${timestamp}"
    fi
}

function create_service() {
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

function restart_service() {
    systemctl daemon-reload
    systemctl restart 6tunnel-setup.service
}

function install() {
    check_root
    check_6tunnel
    check_dialog

    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
    fi

    create_service
    systemctl enable --now 6tunnel-setup.service

    dialog --msgbox "Service installed and enabled.\nConfig file created (or already exists):\n$CONFIG_FILE" 8 60
}

function modify() {
    check_root
    check_dialog
    check_6tunnel

    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --msgbox "No configuration found. Please install the service first." 6 50
        return
    fi

    backup_config

    while true; do
        local options=()
        local i=1
        while read -r src tgt_addr tgt_port; do
            options+=("$i" "$src → $tgt_addr:$tgt_port")
            ((i++))
        done < "$CONFIG_FILE"
        options+=("a" "Add new tunnel")
        options+=("0" "Done editing")

        choice=$(dialog --stdout --menu "Edit your tunnel configuration file:\n$CONFIG_FILE\nSelect tunnel to edit/delete or add new:" 20 70 12 "${options[@]}")

        if [[ "$choice" == "0" || -z "$choice" ]]; then
            break
        elif [[ "$choice" == "a" ]]; then
            local new_src=""
            local new_tgt_addr=""
            local new_tgt_port=""
            while true; do
                new_result=$(dialog --stdout --form "Add new tunnel configuration:" 15 50 3 \
                    "Source port:" 1 1 "$new_src" 1 20 5 0 \
                    "Target address:" 2 1 "$new_tgt_addr" 2 20 30 0 \
                    "Target port:" 3 1 "$new_tgt_port" 3 20 5 0)

                if [ -z "$new_result" ]; then
                    dialog --msgbox "Add cancelled." 6 40
                    break
                fi

                new_src=$(echo "$new_result" | sed -n 1p)
                new_tgt_addr=$(echo "$new_result" | sed -n 2p)
                new_tgt_port=$(echo "$new_result" | sed -n 3p)

                if [[ -z "$new_src" && -z "$new_tgt_addr" && -z "$new_tgt_port" ]]; then
                    dialog --msgbox "Add cancelled." 6 40
                    break
                fi
                if [[ -z "$new_src" || -z "$new_tgt_addr" || -z "$new_tgt_port" ]]; then
                    dialog --msgbox "All fields must be filled or all empty to cancel. Please complete all fields." 7 60
                    continue
                fi

                echo "$new_src $new_tgt_addr $new_tgt_port" >> "$CONFIG_FILE"
                restart_service
                dialog --msgbox "New tunnel added and service restarted." 6 50
                break
            done

        else
            line_content=$(sed -n "${choice}p" "$CONFIG_FILE")
            src=$(echo "$line_content" | awk '{print $1}')
            tgt_addr=$(echo "$line_content" | awk '{print $2}')
            tgt_port=$(echo "$line_content" | awk '{print $3}')

            action=$(dialog --stdout --menu "Edit or delete the tunnel?\n$src → $tgt_addr:$tgt_port" 10 40 2 1 Edit 2 Delete)

            if [[ "$action" == "1" ]]; then
                local edit_src="$src"
                local edit_tgt_addr="$tgt_addr"
                local edit_tgt_port="$tgt_port"
                while true; do
                    new_result=$(dialog --stdout --form "Edit tunnel configuration:" 15 50 3 \
                        "Source port:" 1 1 "$edit_src" 1 20 5 0 \
                        "Target address:" 2 1 "$edit_tgt_addr" 2 20 30 0 \
                        "Target port:" 3 1 "$edit_tgt_port" 3 20 5 0)

                    if [ -z "$new_result" ]; then
                        dialog --msgbox "Edit cancelled, entry unchanged." 6 40
                        break
                    fi

                    edit_src=$(echo "$new_result" | sed -n 1p)
                    edit_tgt_addr=$(echo "$new_result" | sed -n 2p)
                    edit_tgt_port=$(echo "$new_result" | sed -n 3p)

                    if [[ -z "$edit_src" && -z "$edit_tgt_addr" && -z "$edit_tgt_port" ]]; then
                        dialog --msgbox "Edit cancelled, entry unchanged." 6 40
                        break
                    fi
                    if [[ -z "$edit_src" || -z "$edit_tgt_addr" || -z "$edit_tgt_port" ]]; then
                        dialog --msgbox "All fields must be filled or all empty to cancel. Please complete all fields." 7 60
                        continue
                    fi

                    sed -i "${choice}s/.*/$edit_src $edit_tgt_addr $edit_tgt_port/" "$CONFIG_FILE"
                    restart_service
                    dialog --msgbox "Entry updated and service restarted." 6 50
                    break
                done

            elif [[ "$action" == "2" ]]; then
                sed -i "${choice}d" "$CONFIG_FILE"
                restart_service
                dialog --msgbox "Entry deleted and service restarted." 6 50
            fi
        fi
    done
}

function uninstall() {
    check_root
    systemctl disable --now 6tunnel-setup.service || true
    rm -f "$SYSTEMD_UNIT" "$CONFIG_FILE"
    systemctl daemon-reload
    dialog --yesno "Do you want to remove '6tunnel' and 'dialog' packages as well?" 7 60
    if [ $? -eq 0 ]; then
        apt-get remove --purge -y 6tunnel dialog
    fi
    dialog --msgbox "Uninstallation complete." 6 40
}

function main_menu() {
    while true; do
        check_dialog

        choice=$(dialog --stdout --title "6tunnel Setup - v$VERSION" --menu "Choose an option:" 15 70 6 \
            1 "Install service (creates config file, enables service)" \
            2 "Edit tunnel configuration file" \
            3 "Uninstall service and config" \
            4 "About" \
            0 "Exit")

        case "$choice" in
            1) install ;;
            2) modify ;;
            3) uninstall ;;
            4) show_about ;;
            0|"") break ;;
            *) dialog --msgbox "Invalid option." 5 30 ;;
        esac
    done
}

check_root
check_dialog
check_6tunnel
main_menu