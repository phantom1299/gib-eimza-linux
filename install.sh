#!/usr/bin/env bash
# One-time setup for gib-eimza on Ubuntu and other apt-based systems.
# Safe to re-run: it installs only what is missing and asks for sudo only then.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

PACKAGES=(openjdk-8-jre pcscd libccid pcsc-tools curl unzip)
PKCS11_LIB="/usr/lib/libakisp11.so"
# TÜBİTAK's AKİS driver package (Akia), pinned. Set AKIA_DEB=/path/to/Akia_linux_*.deb
# to install a copy you downloaded from https://akiskart.bilgem.tubitak.gov.tr/destek/ instead.
AKIA_URL="https://akiskart.bilgem.tubitak.gov.tr/wp-content/uploads/sites/33/2026/10/Akia_linux_6_8_13.deb_.zip"
AKIA_SHA256="74a0cbcbe6d6bcdfabcb62a25cb4e8f291ba44d986cc8c5734a4e3d3245992a5"
AKIA_HINT="Download Akia for Linux from https://akiskart.bilgem.tubitak.gov.tr/destek/, unzip it, and run:
  AKIA_DEB=/path/to/Akia_linux_<version>.deb ./install.sh"

die() { echo "install.sh: $*" >&2; exit 1; }
installed() { [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" = "install ok installed" ]; }

[ "$(id -u)" -ne 0 ] || die "run this as your normal user; it uses sudo when it needs to."
command -v apt-get >/dev/null || die "this installer needs apt (Ubuntu/Debian). See \"Other distributions\" in README.md."
[ "$(dpkg --print-architecture)" = amd64 ] || die "TÜBİTAK publishes the AKİS driver for amd64 only."

missing=()
for pkg in "${PACKAGES[@]}"; do
  installed "$pkg" && continue
  # A Java 8 from elsewhere (Eclipse Temurin, or JAVA=/path/to/java) is fine too.
  if [ "$pkg" = openjdk-8-jre ] && java8=$(bash ./gib-eimza java 2>/dev/null); then
    echo "==> Using the Java 8 at $java8"
    continue
  fi
  missing+=("$pkg")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "==> Refreshing the package lists"
  sudo apt-get update
  # Not `| grep -q`: with pipefail, apt-cache gets SIGPIPE when grep exits early.
  candidate=$(apt-cache policy openjdk-8-jre 2>/dev/null | sed -n 's/^ *Candidate: //p')
  if [[ " ${missing[*]} " == *" openjdk-8-jre "* ]] && [[ ! "$candidate" =~ ^[0-9] ]]; then
    die "openjdk-8-jre is not in your apt sources (Debian's stable releases don't ship it).
GİB's signer needs Java 8: install one, e.g. Eclipse Temurin 8 from https://adoptium.net/,
then run this installer again. See \"Other distributions\" in README.md."
  fi
  echo "==> Installing ${missing[*]}"
  sudo apt-get install "${missing[@]}"
fi

if [ ! -f "$PKCS11_LIB" ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  if [ -n "${AKIA_DEB:-}" ]; then
    deb=$(readlink -f "$AKIA_DEB")
    [ -f "$deb" ] || die "AKIA_DEB=$AKIA_DEB is not a file."
  else
    echo "==> Downloading TÜBİTAK's AKİS driver (Akia, about 65 MB)"
    curl -fL# -o "$tmp/akia.zip" "$AKIA_URL" || die "could not download $AKIA_URL (TÜBİTAK may have moved it).
$AKIA_HINT"
    echo "$AKIA_SHA256  $tmp/akia.zip" | sha256sum -c --quiet - || die "checksum mismatch for $AKIA_URL (TÜBİTAK may have republished it).
$AKIA_HINT"
    unzip -q -d "$tmp" "$tmp/akia.zip"
    # The zip holds a directory named like the .deb, with the .deb inside it.
    deb=$(find "$tmp" -type f -name '*.deb' -print -quit)
    [ -n "$deb" ] || die "no .deb found in $AKIA_URL.
$AKIA_HINT"
    # apt reads local packages as its unprivileged _apt user.
    chmod -R a+rX "$tmp"
  fi
  echo "==> Installing the AKİS driver"
  sudo apt-get install "$deb"
  [ -f "$PKCS11_LIB" ] || die "the Akia package did not install $PKCS11_LIB"
fi

if ! systemctl is-active --quiet pcscd.socket && ! systemctl is-active --quiet pcscd.service; then
  echo "==> Enabling the smart card service (pcscd)"
  sudo systemctl enable --now pcscd.socket
fi

echo "==> Installing gib-eimza for $USER"
install -Dm755 gib-eimza "$HOME/.local/bin/gib-eimza"
install -Dm644 /dev/stdin "$HOME/.local/share/applications/gib-eimza.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=GİB e-İmza
Comment=Signing app for e-Arşiv Portal (earsivportal.efatura.gov.tr)
Comment[tr]=e-Arşiv Portal (earsivportal.efatura.gov.tr) için imzalama uygulaması
Keywords=e-imza;eimza;GİB;GIB;e-Arşiv;earsiv;efatura;imza;smart card;
Keywords[tr]=e-imza;eimza;GİB;e-Arşiv;earsiv;efatura;imza;akıllı kart;
Exec="$HOME/.local/bin/gib-eimza"
Icon=application-certificate
Terminal=false
StartupNotify=false
Categories=Office;
EOF

echo "==> Downloading GİB's signing app"
"$HOME/.local/bin/gib-eimza" update

echo
"$HOME/.local/bin/gib-eimza" check || true

echo
echo "Done. Start \"GİB e-İmza\" from your app menu, or run: gib-eimza"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Note: ~/.local/bin is not on your PATH yet. Log out and back in, or run ~/.local/bin/gib-eimza." ;;
esac
