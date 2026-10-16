#!/bin/bash
# File Cracker - single-file installer for all Linux distros
# Usage: bash filecracker-kur.sh
# Supports: Arch/CachyOS, Debian/Ubuntu, Fedora, openSUSE (+derivatives)
# This file is self-contained: program files are embedded at the bottom.
# Installs: dependencies + app + icon + shortcuts (menu + desktop)
set -u
APP=filecracker
BIN=/usr/bin/filecracker
LIB=/usr/lib/filecracker

# ---- embedded program files (no external files needed) ----
TMP_SRC="$(mktemp -d)"
trap 'rm -rf "$TMP_SRC"' EXIT
if [[ -n "${FC_SRC:-}" && -f "$FC_SRC/filecracker.py" ]]; then
  PROJE="$FC_SRC"  # dev hook: source dir can be given externally
else
  awk '/^__PAYLOAD__$/{f=1;next} f' "$0" | base64 -d | tar -xz -C "$TMP_SRC"
  PROJE="$TMP_SRC"
fi

echo "== installing $APP =="
SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

# ---- distro detection ----
ID=unknown; LIKE=""
if [[ -f /etc/os-release ]]; then # shellcheck disable=SC1091
  . /etc/os-release
  ID="${ID:-unknown}"; LIKE="${ID_LIKE:-}"
fi
echo "Distro: $ID (like: ${LIKE:-none})"

install_arch() {
  local MGR="sudo pacman -S --needed --noconfirm"
  if command -v yay >/dev/null 2>&1; then MGR="yay -S --needed --noconfirm"
  elif command -v paru >/dev/null 2>&1; then MGR="paru -S --needed --noconfirm"; fi
  echo "Package manager: $MGR"
  $MGR python-pyqt6 hashcat john qpdf p7zip zip pdfrip 2>/dev/null \
    || sudo pacman -S --needed --noconfirm python-pyqt6 hashcat john qpdf p7zip zip || true
  # rar and unrar conflict: one is enough, else try unrar
  if ! command -v unrar >/dev/null 2>&1 && ! command -v rar >/dev/null 2>&1; then
    ($MGR unrar 2>/dev/null || sudo pacman -S --needed --noconfirm unrar) || true
  fi
  if ! perl -MCompress::Raw::Lzma -e1 >/dev/null 2>&1; then
    echo "Installing perl-compress-raw-lzma (for 7z2john, AUR)..."
    (yay -S --needed --noconfirm perl-compress-raw-lzma 2>/dev/null \
      || paru -S --needed --noconfirm perl-compress-raw-lzma 2>/dev/null \
      || echo "WARNING: perl-compress-raw-lzma failed, 7z support may be missing") || true
  fi
}

install_deb() {
  echo "Package manager: apt"
  $SUDO apt update
  $SUDO apt install -y python3-pyqt6 hashcat john qpdf p7zip-full unrar zip libcompress-raw-lzma-perl 2>/dev/null \
    || $SUDO apt install -y python3-pyqt6 hashcat john qpdf p7zip-full unrar-free zip || true
  # pdfrip Debian/Ubuntu depolarinda yok -> pip ile (opsiyonel, sadece PDF CPU yedegi)
  if ! command -v pdfrip >/dev/null 2>&1; then
    (pipx install pdfrip 2>/dev/null || pip install --user --break-system-packages pdfrip 2>/dev/null \
      || echo "INFO: pdfrip failed (optional, no PDF CPU fallback)") || true
  fi
}

install_fedora() {
  echo "Package manager: dnf"
  $SUDO dnf install -y python3-qt6 hashcat john qpdf p7zip unrar zip perl-Compress-Raw-Lzma 2>/dev/null \
    || $SUDO dnf install -y python3-qt6 hashcat john qpdf p7zip zip || true
  if ! command -v pdfrip >/dev/null 2>&1; then
    (pipx install pdfrip 2>/dev/null || pip install --user --break-system-packages pdfrip 2>/dev/null \
      || echo "INFO: pdfrip failed (optional)") || true
  fi
}

install_suse() {
  echo "Package manager: zypper"
  $SUDO zypper --non-interactive install python3-qt6 hashcat john qpdf p7zip unrar zip perl-Compress-Raw-Lzma 2>/dev/null \
    || $SUDO zypper --non-interactive install python3-qt6 hashcat john qpdf p7zip zip || true
  if ! command -v pdfrip >/dev/null 2>&1; then
    (pipx install pdfrip 2>/dev/null || pip install --user --break-system-packages pdfrip 2>/dev/null \
      || echo "INFO: pdfrip failed (optional)") || true
  fi
}

case "$ID $LIKE" in
  *arch*|*cachy*|*endeavour*|*manjaro*) install_arch ;;
  *debian*|*ubuntu*|*mint*|*pop*)       install_deb ;;
  *fedora*|*rhel*|*centos*|*rocky*|*alma*) install_fedora ;;
  *suse*|*opensuse*)                    install_suse ;;
  *)
    if command -v pacman >/dev/null 2>&1; then install_arch
    elif command -v apt >/dev/null 2>&1; then install_deb
    elif command -v dnf >/dev/null 2>&1; then install_fedora
    elif command -v zypper >/dev/null 2>&1; then install_suse
    else
      echo "ERROR: unknown distro. Install these packages manually:"
      echo "  python Qt6 bindings, hashcat, john, qpdf, p7zip, unrar/rar, (optional) pdfrip"
      exit 1
    fi ;;
esac

# ---- missing-tool warnings ----
for t in hashcat john qpdf; do
  command -v "$t" >/dev/null 2>&1 || echo "WARNING: $t not found, related formats will not work"
done
command -v pdfrip >/dev/null 2>&1 || echo "INFO: pdfrip missing (only the PDF CPU fallback is unavailable)"
perl -MCompress::Raw::Lzma -e1 >/dev/null 2>&1 || echo "INFO: perl LZMA module missing (7z hash extraction will not work)"

if [[ ! -f "$PROJE/filecracker.py" ]]; then
  echo "ERROR: embedded program could not be extracted."
  exit 1
fi
echo "Source: embedded package"

# ---- clean up old v1 (filecracker-gpu) leftovers ----
$SUDO rm -rf /usr/lib/filecracker-gpu \
  /usr/bin/filecracker-gpu \
  /usr/share/applications/filecracker-gpu.desktop \
  /usr/share/icons/hicolor/scalable/apps/filecracker-gpu.svg \
  "$HOME/Masaüstü/filecracker-gpu.desktop" "$HOME/Desktop/filecracker-gpu.desktop" 2>/dev/null || true

# ---- files ----
if pacman -Q filecracker >/dev/null 2>&1; then
  echo "AUR package already installed -> not overwriting files (db stays consistent)."
else
$SUDO install -Dm755 "$PROJE/filecracker.py" "$LIB/filecracker.py"
$SUDO install -Dm644 "$PROJE/common-passwords.txt" "$LIB/common-passwords.txt"
$SUDO install -Dm644 "$PROJE/filecracker.svg" /usr/share/icons/hicolor/scalable/apps/filecracker.svg
$SUDO install -Dm644 "$PROJE/filecracker.desktop" /usr/share/applications/filecracker.desktop
printf '#!/bin/sh\nexec python3 /usr/lib/filecracker/filecracker.py "$@"\n' | $SUDO tee "$BIN" >/dev/null
$SUDO chmod 755 "$BIN"
$SUDO ln -sf filecracker /usr/bin/pdfcracker || true
fi

# ---- desktop shortcut ----
for MD in "/home/$USER/Masaüstü" "/home/$USER/Desktop" "$HOME/Desktop"; do
  if [[ -d "$MD" ]]; then
    cp -f /usr/share/applications/filecracker.desktop "$MD/" 2>/dev/null || true
    chmod +x "$MD/filecracker.desktop" 2>/dev/null || true
    gio set "$MD/filecracker.desktop" metadata::trusted true 2>/dev/null || true
  fi
done
$SUDO update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || $SUDO gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true

echo
echo "Done. Run: filecracker  (menu: File Cracker)"
echo "GPU: hashcat uses ALL cards it finds (NVIDIA + AMD + Intel). Weak GPU? Pick 'CPU Crack' in the window."
exit 0
__PAYLOAD__
