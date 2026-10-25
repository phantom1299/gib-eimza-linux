#!/usr/bin/env bash
# Remove gib-eimza's per-user files. System packages are left installed because
# other smart card software may use them; the command to remove them is printed.
set -euo pipefail

if [ -n "$(ss -Hltn 'sport = :8543' 2>/dev/null)" ]; then
  echo "The signing app is still running. Close its window first." >&2
  exit 1
fi

rm -f "$HOME/.local/bin/gib-eimza" "$HOME/.local/share/applications/gib-eimza.desktop"
rm -rf "${GIB_EIMZA_DATA:-$HOME/.local/share/gib-eimza}"
echo "Removed gib-eimza."
echo
echo "GİB's signer and the AKİS driver also leave files in your home folder."
echo "Delete them if you no longer need them:"
echo "  rm -rf ~/cssign.properties ~/certificates ~/crls ~/trustedRoots ~/Akisp11 /tmp/EFaturaWebSocketLog"
echo
echo "To remove the system packages as well:"
echo "  sudo apt remove akia openjdk-8-jre openjdk-8-jre-headless pcsc-tools"
echo "  (keep pcscd and libccid if other smart card software uses them)"
