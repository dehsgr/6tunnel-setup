#!/bin/bash

VERSION="1.2.0"

CONFIG_FILE="/etc/6tunnel-setup.conf"
BACKUP_FILE="/etc/6tunnel-setup.conf.bak"
SERVICE_NAME="6tunnel-setup.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
LAUNCHER_SCRIPT="/usr/local/bin/6tunnel-launcher.sh"

set -e

function cleanup {
    tput sgr0
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
    dialog --title "About" --msgbox "6tunnel-setup\nVersion: $VERSION\nAuthor: dehsgr\nLicense: ISC" 10 50 || true
}

function backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        timestamp=$(date +"%Y%m%d_%H%M%S")
        cp "$CONFIG_FILE" "${BACKUP_FILE}.${timestamp}"
    fi
}

create_service() {
    if [ ! -f "$LAUNCHER_SCRIPT" ]; then
        cat <<EOF > "$LAUNCHER_SCRIPT"
#!/bin/bash

CONFIG_FILE="$CONFIG_FILE"
PID_FILE="/run/6tunnel-pids"

cleanup() {
    echo "Stopping all 6tunnel processes…"
    if [[ -f "\$PID_FILE" ]]; then
        while read -r pid; do
            kill "\$pid" 2>/dev/null
        done < "\$PID_FILE"
        rm -f "\$PID_FILE"
    fi
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "Starting 6tunnel processes…"
> "\$PID_FILE"

while read -r src addr port name; do
    [[ -z "\$src" ]] && continue
    echo "Starting 6tunnel: \$src -> \$addr:\$port"
    /usr/bin/6tunnel "\$src" "\$addr" "\$port" &
    echo \$! >> "\$PID_FILE"
done < "\$CONFIG_FILE"

echo "All tunnels started."

# Keep the process alive so systemd can track it
tail -f /dev/null
EOF

        chmod +x "$LAUNCHER_SCRIPT"
    fi

    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=6tunnel Setup Service
After=network.target

[Service]
Type=simple
Environment=CONFIG_FILE=$CONFIG_FILE
ExecStart=$LAUNCHER_SCRIPT
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    echo "Service $SERVICE_NAME wurde erstellt und aktiviert."
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

    dialog --msgbox "Service installed and enabled.\nConfig file created (or already exists):\n$CONFIG_FILE" 8 60 || true
}

function modify() {
    check_root
    check_dialog
    check_6tunnel

    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --msgbox "No configuration found. Please install the service first." 6 50 || true
        return
    fi

    backup_config

    while true; do
        local options=()
        local i=1
        while IFS= read -r line_content; do
            src=$(echo "$line_content" | awk '{print $1}')
            tgt_addr=$(echo "$line_content" | awk '{print $2}')
            tgt_port=$(echo "$line_content" | awk '{print $3}')
            name=$(echo "$line_content" | cut -d' ' -f4- | sed 's/^"\(.*\)"$/\1/')
            if [ -n "$name" ]; then
                display_name="$name"
            else
                display_name="$src → $tgt_addr:$tgt_port"
            fi
            options+=("$i" "$display_name")
            ((i++))
        done < "$CONFIG_FILE"
        options+=("a" "Add new tunnel")
        options+=("0" "Done editing")

		set +e
        choice=$(dialog --stdout --menu "Edit your tunnel configuration file:\n$CONFIG_FILE\nSelect tunnel to edit/delete or add new:" 20 70 12 "${options[@]}")
		ret=$?
		set -e
		if [[ $ret -ne 0 ]]; then
			break
		fi

        case "$choice" in
            0) break ;;
            "") continue ;;
            a)
                local new_src="" new_tgt_addr="" new_tgt_port="" new_name=""
                while true; do
					set +e
                    new_result=$(dialog --stdout --form "Add new tunnel configuration:" 15 50 4 \
                        "Source port:" 1 1 "$new_src" 1 20 5 0 \
                        "Target address:" 2 1 "$new_tgt_addr" 2 20 30 0 \
                        "Target port:" 3 1 "$new_tgt_port" 3 20 5 0 \
                        "Name (optional):" 4 1 "$new_name" 4 20 20 0)
					ret=$?
					set -e
                    if [[ $ret -ne 0 || -z "$new_result" ]]; then
                        break
                    fi
                    new_src=$(echo "$new_result" | sed -n 1p)
                    new_tgt_addr=$(echo "$new_result" | sed -n 2p)
                    new_tgt_port=$(echo "$new_result" | sed -n 3p)
                    new_name=$(echo "$new_result" | sed -n 4p)

                    if [[ -z "$new_src" || -z "$new_tgt_addr" || -z "$new_tgt_port" ]]; then
                        dialog --msgbox "All required fields must be filled. Please complete all fields." 7 60 || true
                        continue
                    fi

                    echo "$new_src $new_tgt_addr $new_tgt_port \"$new_name\"" >> "$CONFIG_FILE"
                    restart_service
                    dialog --msgbox "New tunnel added and service restarted." 6 50 || true
                    break
                done
                ;;
            *)
                line_content=$(sed -n "${choice}p" "$CONFIG_FILE")
                src=$(echo "$line_content" | awk '{print $1}')
                tgt_addr=$(echo "$line_content" | awk '{print $2}')
                tgt_port=$(echo "$line_content" | awk '{print $3}')
                name=$(echo "$line_content" | cut -d' ' -f4- | sed 's/^"\(.*\)"$/\1/')
				if [ -n "$name" ]; then
					display_name="$name"
				else
					display_name="$src → $tgt_addr:$tgt_port"
				fi

				set +e
                action=$(dialog --stdout --menu "Edit or delete the tunnel?\n$display_name" 10 40 2 1 Edit 2 Delete)
				ret=$?
				set -e
                if [[ $ret -ne 0 ]]; then
                    continue
                fi

                if [[ "$action" == "1" ]]; then
                    local edit_src="$src" edit_tgt_addr="$tgt_addr" edit_tgt_port="$tgt_port" edit_name="$name"
                    while true; do
						set +e
                        new_result=$(dialog --stdout --form "Edit tunnel configuration:" 15 50 4 \
                            "Source port:" 1 1 "$edit_src" 1 20 5 0 \
                            "Target address:" 2 1 "$edit_tgt_addr" 2 20 30 0 \
                            "Target port:" 3 1 "$edit_tgt_port" 3 20 5 0 \
                            "Name (optional):" 4 1 "$edit_name" 4 20 20 0)
						ret=$?
						set -e
                        if [[ $ret -ne 0 || -z "$new_result" ]]; then
                            break
                        fi
                        edit_src=$(echo "$new_result" | sed -n 1p)
                        edit_tgt_addr=$(echo "$new_result" | sed -n 2p)
                        edit_tgt_port=$(echo "$new_result" | sed -n 3p)
                        edit_name=$(echo "$new_result" | sed -n 4p)

                        if [[ -z "$edit_src" || -z "$edit_tgt_addr" || -z "$edit_tgt_port" ]]; then
                            dialog --msgbox "All required fields must be filled. Please complete all fields." 7 60 || true
                            continue
                        fi

                        sed -i "${choice}s@.*@${edit_src} ${edit_tgt_addr} ${edit_tgt_port} \"${edit_name}\"@" "$CONFIG_FILE"
                        restart_service
                        dialog --msgbox "Tunnel updated and service restarted." 6 50 || true
                        break
                    done
                elif [[ "$action" == "2" ]]; then
                    sed -i "${choice}d" "$CONFIG_FILE"
                    restart_service
                    dialog --msgbox "Tunnel deleted and service restarted." 6 50 || true
                fi
                ;;
        esac
    done
}

function uninstall() {
    check_root
    systemctl disable --now 6tunnel-setup.service || true
    rm -f "$SERVICE_FILE" "$CONFIG_FILE" "$LAUNCHER_SCRIPT"
    systemctl daemon-reload
    if dialog --yesno "Do you want to remove '6tunnel' and 'dialog' packages as well?" 7 60; then
        apt-get remove --purge -y 6tunnel dialog
    fi
    dialog --msgbox "Uninstallation complete." 6 40 || true
}

function main_menu() {
    while true; do
        check_dialog

        local options=()
        local installed=0

        if [ -f "$SERVICE_FILE" ] || [ -f "$LAUNCHER_SCRIPT" ] || [ -f "$CONFIG_FILE" ]; then
            installed=1
        fi

        if [ "$installed" -eq 1 ]; then
            options+=("1" "Install service (already installed)")
            options+=("2" "Edit tunnel configuration file")
            options+=("3" "Uninstall service and config")
        else
            options+=("1" "Install service (creates config file, enables service)")
            options+=("2" "Edit tunnel configuration file (not available)")
            options+=("3" "Uninstall service and config (not available)")
        fi

        options+=("4" "About")
        options+=("0" "Exit")

        choice=$(dialog --stdout --title "6tunnel Setup - v$VERSION" --menu "Choose an option:" 15 70 6 "${options[@]}")

        case "$choice" in
            1)
                if [ "$installed" -eq 1 ]; then
                    dialog --msgbox "Service is already installed. Please uninstall first if you want to reinstall." 7 50 || true
                else
                    install
                fi
                ;;
            2)
                if [ "$installed" -eq 0 ]; then
                    dialog --msgbox "No configuration found. Please install the service first." 7 50 || true
                else
                    modify
                fi
                ;;
            3)
                if [ "$installed" -eq 0 ]; then
                    dialog --msgbox "Nothing to uninstall. Service is not installed." 7 50 || true
                else
                    uninstall
                fi
                ;;
            4) show_about ;;
            0) break ;;
        esac
    done
}

check_root
check_dialog
check_6tunnel
main_menu