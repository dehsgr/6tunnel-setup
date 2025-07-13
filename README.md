# 6tunnel-setup

**Version:** 1.0.0  
**License:** MIT  
**Author:** [dehsgr](https://github.com/dehsgr)

## 📖 Overview

`6tunnel-setup` is a **menu-driven Bash script** to configure and manage `6tunnel` as a system service on Debian/Ubuntu-based Linux systems.

It provides a user-friendly interface for setting up IPv6-to-IPv4 port forwarding, ensuring the tunnels run at boot via `systemd`.

The script also takes care of required dependencies, optionally installs/uninstalls them, and keeps backups of your configurations.

---

## 🚀 Features

✅ Interactive, menu-based interface (via `dialog`)  
✅ Install, modify, or uninstall tunnels easily  
✅ Supports multiple tunnels (source port → target host:port)  
✅ Validates input formats  
✅ Automatically installs missing dependencies (`6tunnel`, `dialog`) if desired  
✅ Creates a `systemd` unit to run at boot as root  
✅ Automatically backs up configuration before changes  
✅ Shows version info in an About menu  
✅ Localized in **English (en-us)**  
✅ Optionally removes dependencies during uninstall  

---

## 🖥️ Requirements

- Linux (Debian/Ubuntu recommended)
- root privileges
- Bash
- `dialog` and `6tunnel` (the script can install these automatically)

---

## 🔧 Installation & Usage

### 📥 Download the script

Clone the repository:
```bash
git clone https://github.com/dehsgr/6tunnel-setup.git
cd 6tunnel-setup
```

Make the script executable:
```bash
chmod +x 6tunnel-setup.sh
```

### 🚀 Run the script
Run the script as **root**:
```bash
sudo ./6tunnel-setup.sh
```

You will be presented with a menu:
- **Install**: Configure new tunnels and enable the systemd service.
- **Modify configuration**: Edit existing tunnels.
- **Uninstall**: Remove the service, configuration, and optionally uninstall dependencies.
- **About**: Show version and author.
- **Exit**: Close the script.

---

## 📝 Configuration format

Each tunnel consists of:
```
source_port target_address target_port
```

For example:
```
8080 192.168.1.100 80
8443 example.com 443
```

The script validates these entries before saving.

---

## 🗑️ Uninstallation

To completely remove the setup (including dependencies), choose `Uninstall` from the menu and confirm the removal of dependencies when prompted.

---

## 📄 Changelog

See [CHANGELOG.md](CHANGELOG.md) or the [Releases](https://github.com/dehsgr/6tunnel-setup/releases) page.

---

## 🧑‍💻 Contributing

Issues and pull requests are welcome! Please open an issue to discuss changes before submitting a PR.

---

## 📜 License

This project is licensed under the ISC License — see the [LICENSE](LICENSE) file for details.