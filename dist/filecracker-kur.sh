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
p8/pc/qcPqc16X8Bm6GdLwDIAAA=
