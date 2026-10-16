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
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
