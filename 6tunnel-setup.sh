#!/bin/bash

SCRIPT_VERSION="1.0.0"

SERVICE_SCRIPT="/usr/local/bin/6tunnel-start.sh"
SYSTEMD_UNIT="/etc/systemd/system/6tunnel-start.service"
CONFIG_FILE="$SERVICE_SCRIPT.config"
LOGFILE="/var/log/6tunnel-setup.log"
BACKUP_DIR="/var/backups"
AUTO_MODE=0
INSTALLED_PACKAGES=()

trap clear EXIT

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOGFILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root!"
        exit 1
    fi
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

detect_pkg_manager() {
    if check_command apt-get; then echo "apt-get"
    elif check_command dnf; then echo "dnf"
    elif check_command yum; then echo "yum"
    elif check_command zypper; then echo "zypper"
    elif check_command pacman; then echo "pacman"
    else echo ""
    fi
}

install_packages() {
    local pkgs=("$@")
    local pmgr
    pmgr=$(detect_pkg_manager)
    if [[ -z "$pmgr" ]]; then
        log "No supported package manager found. Please install manually: ${pkgs[*]}"
        exit 1
    fi

    log "Installing packages: ${pkgs[*]}"
    case "$pmgr" in
        apt-get) apt-get update >>"$LOGFILE" 2>&1 && apt-get install -y "${pkgs[@]}" >>"$LOGFILE" 2>&1 ;;
        dnf) dnf install -y "${pkgs[@]}" >>"$LOGFILE" 2>&1 ;;
        yum) yum install -y "${pkgs[@]}" >>"$LOGFILE" 2>&1 ;;
        zypper) zypper install -y "${pkgs[@]}" >>"$LOGFILE" 2>&1 ;;
        pacman) pacman -Sy --noconfirm "${pkgs[@]}" >>"$LOGFILE" 2>&1 ;;
    esac

    INSTALLED_PACKAGES+=("${pkgs[@]}")
}

ensure_dependency() {
    local dep="$1"
    if ! check_command "$dep"; then
        dialog --yesno "The required package '$dep' is not installed.\n\nInstall it now?" 10 50
        if [[ $? -eq 0 ]]; then
            install_packages "$dep"
        else
            log "User declined installation of $dep. Exiting."
            exit 1
        fi
    fi
}

backup_config() {
    mkdir -p "$BACKUP_DIR"
    if [[ -f "$CONFIG_FILE" ]]; then
        local ts
        ts=$(date '+%Y%m%d-%H%M%S')
        cp "$CONFIG_FILE" "$BACKUP_DIR/6tunnel-config.$ts.bak"
        log "Backup of config created: $BACKUP_DIR/6tunnel-config.$ts.bak"
    fi
}

generate_start_script() {
    echo "#!/bin/bash" > "$SERVICE_SCRIPT"
    while read -r SRC TARGET TPORT; do
        [[ -z "$SRC" || -z "$TARGET" || -z "$TPORT" ]] && continue
        echo "6tunnel $SRC $TARGET $TPORT" >> "$SERVICE_SCRIPT"
    done < "$CONFIG_FILE"
    chmod +x "$SERVICE_SCRIPT"
}

create_service() {
cat <<EOF > "$SYSTEMD_UNIT"
[Unit]
Description=6tunnel Startup Script

[Service]
Type=oneshot
ExecStart=$SERVICE_SCRIPT
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable 6tunnel-start.service
}

do_install() {
    ensure_dependency 6tunnel
    backup_config
    : > "$CONFIG_FILE"

    while true; do
        SRC_PORT=$(dialog --inputbox "Enter source port (leave blank to finish):" 10 50 3>&1 1>&2 2>&3)
        [[ $? -ne 0 || -z "$SRC_PORT" ]] && break
        if ! [[ "$SRC_PORT" =~ ^[0-9]+$ ]]; then
            dialog --msgbox "Invalid source port." 8 50
            continue
        fi

        TARGET_ADDR=$(dialog --inputbox "Enter target IP/hostname:" 10 50 3>&1 1>&2 2>&3)
        [[ $? -ne 0 || -z "$TARGET_ADDR" ]] && break

        TARGET_PORT=$(dialog --inputbox "Enter target port:" 10 50 3>&1 1>&2 2>&3)
        [[ $? -ne 0 || -z "$TARGET_PORT" ]] && break
        if ! [[ "$TARGET_PORT" =~ ^[0-9]+$ ]]; then
            dialog --msgbox "Invalid target port." 8 50
            continue
        fi

        echo "$SRC_PORT $TARGET_ADDR $TARGET_PORT" >> "$CONFIG_FILE"
    done

    if [[ -s "$CONFIG_FILE" ]]; then
        generate_start_script
        create_service
        log "Installation completed."
        dialog --msgbox "Installation completed. Service enabled." 8 50
    else
        rm -f "$CONFIG_FILE" "$SERVICE_SCRIPT"
        log "No entries entered. Installation aborted."
        dialog --msgbox "No entries entered. Installation aborted." 8 50
    fi
}

do_modify() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        dialog --msgbox "No configuration found. Please install first." 8 50
        return
    fi
    backup_config

    NEW=$(dialog --editbox "$CONFIG_FILE" 20 70 3>&1 1>&2 2>&3)
    if [[ $? -eq 0 ]]; then
        VALID=1
        while read -r line; do
            [[ -z "$line" ]] && continue
            if ! [[ "$line" =~ ^[0-9]+\ +[^ ]+\ +[0-9]+$ ]]; then
                VALID=0
                dialog --msgbox "Invalid line:\n$line\nChanges not saved." 10 50
                break
            fi
        done <<< "$NEW"

        if [[ $VALID -eq 1 ]]; then
            echo "$NEW" > "$CONFIG_FILE"
            generate_start_script
            log "Configuration modified."
            dialog --msgbox "Configuration updated." 8 50
        fi
    fi
}

do_uninstall() {
    backup_config
    systemctl disable 6tunnel-start.service
    rm -f "$CONFIG_FILE" "$SERVICE_SCRIPT" "$SYSTEMD_UNIT"
    systemctl daemon-reload

    dialog --yesno "Do you also want to remove the installed dependencies (6tunnel, dialog)?" 10 50
    if [[ $? -eq 0 ]]; then
        local pmgr
        pmgr=$(detect_pkg_manager)
        case "$pmgr" in
            apt-get) apt-get remove --purge -y 6tunnel dialog ;;
            dnf) dnf remove -y 6tunnel dialog ;;
            yum) yum remove -y 6tunnel dialog ;;
            zypper) zypper remove -y 6tunnel dialog ;;
            pacman) pacman -Rns --noconfirm 6tunnel dialog ;;
        esac
        log "Dependencies removed."
    fi

    log "Uninstallation completed."
    dialog --msgbox "Uninstallation completed." 8 50
}

show_about() {
    dialog --msgbox "6tunnel Setup Script\n\nVersion: $SCRIPT_VERSION\n\nCopyright (c) 2025 by dehsgr" \
        12 50
}

main_menu() {
    while true; do
        MENU_ITEMS=()
        MENU_ITEMS+=("1" "Install")

        [[ -f "$CONFIG_FILE" ]] && MENU_ITEMS+=("2" "Modify configuration")
        [[ -f "$CONFIG_FILE" || -f "$SYSTEMD_UNIT" ]] && MENU_ITEMS+=("3" "Uninstall")
        MENU_ITEMS+=("4" "About")
        MENU_ITEMS+=("5" "Exit")

        CHOICE=$(dialog --clear --backtitle "6tunnel Setup v$SCRIPT_VERSION" \
            --title "Main Menu" \
            --menu "Choose an option:" 15 50 6 \
            "${MENU_ITEMS[@]}" \
            3>&1 1>&2 2>&3)

        case "$CHOICE" in
            1) do_install ;;
            2) do_modify ;;
            3) do_uninstall ;;
            4) show_about ;;
            5) clear; exit ;;
            *) break ;;
        esac
    done
}

# Start
check_root
ensure_dependency dialog
main_menu