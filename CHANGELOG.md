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

## [1.1.0] – 2025-07-17
### Added
- Display of **name** in the tunnel configuration edit menu if new name field is specified for the tunnel.

### Fixed
- Canceling or pressing ESC in some dialogs causes the script to exit instead of returning to the menu.

## [1.2.0] – 2025-07-17
### Fixed
- 6tunnels weren't fired up correctly. Whole systemd unit revised.