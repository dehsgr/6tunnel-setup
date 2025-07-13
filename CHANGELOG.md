# Changelog

## [1.0.0] - 2025-07-13
### Added
- Initial public release of the 6tunnel setup script.
- Menu-driven installer and uninstaller with `dialog` interface.
- Supports installation, modification, and removal of 6tunnel systemd startup service.
- Prompts user-friendly dialogs to configure multiple tunnels (source port → target host:port).
- Validates input and creates systemd unit to start at boot as root.
- Automatically checks for and optionally installs required dependencies (`6tunnel`, `dialog`).
- Automatically cleans up and optionally removes dependencies during uninstallation.
- Backups the current configuration on every change.