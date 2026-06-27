#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_HELPER="${SCRIPT_DIR}/game-mode-governor"
INSTALL_TARGET="/usr/local/bin/game-mode-governor"
SUDOERS_FILE="/etc/sudoers.d/game-mode-governor"
TARGET_USER="${1:-${SUDO_USER:-}}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: this script must be run as root (via sudo)" >&2
  exit 1
fi

if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" || ! "${TARGET_USER}" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
  echo "Error: could not determine a safe target user (run via sudo or pass the username)" >&2
  exit 1
fi

if [[ ! -f "${REPO_HELPER}" ]]; then
  echo "Error: repo copy not found: ${REPO_HELPER}" >&2
  exit 1
fi

# Install the governor helper
install -o root -g root -m 0755 "${REPO_HELPER}" "${INSTALL_TARGET}"
echo "Installed: ${INSTALL_TARGET}"

# Write sudoers rule
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/game-mode-governor performance, /usr/local/bin/game-mode-governor powersave\n' \
  "${TARGET_USER}" > "${SUDOERS_FILE}"
chmod 0440 "${SUDOERS_FILE}"
echo "Written: ${SUDOERS_FILE}"

# Validate sudoers file — abort and remove if invalid
if ! visudo -cf "${SUDOERS_FILE}"; then
  echo "Error: sudoers file validation failed. Removing." >&2
  rm -f "${SUDOERS_FILE}"
  exit 1
fi

echo "game-mode-governor install complete."
echo "Authorized user: ${TARGET_USER}"
echo "CPU governor switching is now available without a password prompt."
