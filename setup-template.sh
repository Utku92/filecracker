#!/bin/bash
# File Cracker - tum Linux dagitimlari icin tek dosya kurulum
# Kullanim: bash filecracker-kur.sh
# Destek: Arch/CachyOS, Debian/Ubuntu, Fedora, openSUSE (+turevleri)
# Bu dosya tek basina yeter: program dosyalari en altta gomuludur.
# Yapar: bagimliliklar + uygulama + simge + kisayol (menu + masaustu)
set -u
APP=filecracker
BIN=/usr/bin/filecracker
LIB=/usr/lib/filecracker

# ---- gomulu program dosyalari (harici dosyaya gerek yok) ----
TMP_SRC="$(mktemp -d)"
trap 'rm -rf "$TMP_SRC"' EXIT
if [[ -n "${FC_SRC:-}" && -f "$FC_SRC/filecracker.py" ]]; then
  PROJE="$FC_SRC"  # gelistirici kancasi: kaynak dizini disaridan verilebilir
else
  awk '/^__PAYLOAD__$/{f=1;next} f' "$0" | base64 -d | tar -xz -C "$TMP_SRC"
  PROJE="$TMP_SRC"
fi

echo "== $APP kurulumu =="
SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

# ---- dagitim tespiti ----
ID=unknown; LIKE=""
if [[ -f /etc/os-release ]]; then # shellcheck disable=SC1091
  . /etc/os-release
  ID="${ID:-unknown}"; LIKE="${ID_LIKE:-}"
fi
echo "Dagitim: $ID (benzer: ${LIKE:-yok})"

install_arch() {
  local MGR="sudo pacman -S --needed --noconfirm"
  if command -v yay >/dev/null 2>&1; then MGR="yay -S --needed --noconfirm"
  elif command -v paru >/dev/null 2>&1; then MGR="paru -S --needed --noconfirm"; fi
  echo "Paket yoneticisi: $MGR"
  $MGR python-pyqt6 hashcat john qpdf p7zip zip pdfrip 2>/dev/null \
    || sudo pacman -S --needed --noconfirm python-pyqt6 hashcat john qpdf p7zip zip || true
  # rar ve unrar cakisir: biri varsa yeter, yoksa unrar dene
  if ! command -v unrar >/dev/null 2>&1 && ! command -v rar >/dev/null 2>&1; then
    ($MGR unrar 2>/dev/null || sudo pacman -S --needed --noconfirm unrar) || true
  fi
  if ! perl -MCompress::Raw::Lzma -e1 >/dev/null 2>&1; then
    echo "perl-compress-raw-lzma kuruluyor (7z2john icin, AUR)..."
    (yay -S --needed --noconfirm perl-compress-raw-lzma 2>/dev/null \
      || paru -S --needed --noconfirm perl-compress-raw-lzma 2>/dev/null \
      || echo "UYARI: perl-compress-raw-lzma kurulamadi, 7z destegi eksik kalabilir") || true
  fi
}

install_deb() {
  echo "Paket yoneticisi: apt"
  $SUDO apt update
  $SUDO apt install -y python3-pyqt6 hashcat john qpdf p7zip-full unrar zip libcompress-raw-lzma-perl 2>/dev/null \
    || $SUDO apt install -y python3-pyqt6 hashcat john qpdf p7zip-full unrar-free zip || true
  # pdfrip Debian/Ubuntu depolarinda yok -> pip ile (opsiyonel, sadece PDF CPU yedegi)
  if ! command -v pdfrip >/dev/null 2>&1; then
    (pipx install pdfrip 2>/dev/null || pip install --user --break-system-packages pdfrip 2>/dev/null \
      || echo "BILGI: pdfrip kurulamadi (opsiyonel, PDF CPU yedegi olmaz)") || true
  fi
}

install_fedora() {
  echo "Paket yoneticisi: dnf"
  $SUDO dnf install -y python3-qt6 hashcat john qpdf p7zip unrar zip perl-Compress-Raw-Lzma 2>/dev/null \
    || $SUDO dnf install -y python3-qt6 hashcat john qpdf p7zip zip || true
  if ! command -v pdfrip >/dev/null 2>&1; then
    (pipx install pdfrip 2>/dev/null || pip install --user --break-system-packages pdfrip 2>/dev/null \
      || echo "BILGI: pdfrip kurulamadi (opsiyonel)") || true
  fi
}

install_suse() {
  echo "Paket yoneticisi: zypper"
  $SUDO zypper --non-interactive install python3-qt6 hashcat john qpdf p7zip unrar zip perl-Compress-Raw-Lzma 2>/dev/null \
    || $SUDO zypper --non-interactive install python3-qt6 hashcat john qpdf p7zip zip || true
  if ! command -v pdfrip >/dev/null 2>&1; then
    (pipx install pdfrip 2>/dev/null || pip install --user --break-system-packages pdfrip 2>/dev/null \
      || echo "BILGI: pdfrip kurulamadi (opsiyonel)") || true
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
      echo "HATA: bilinmeyen dagitim. Su paketleri elle kurun:"
      echo "  python-Qt6 baglamasi, hashcat, john, qpdf, p7zip, unrar/rar, (opsiyonel) pdfrip"
      exit 1
    fi ;;
esac

# ---- eksik uyari ----
for t in hashcat john qpdf; do
  command -v "$t" >/dev/null 2>&1 || echo "UYARI: $t bulunamadi, ilgili formatlar calismaz"
done
command -v pdfrip >/dev/null 2>&1 || echo "BILGI: pdfrip yok (sadece PDF CPU yedegi eksik)"
perl -MCompress::Raw::Lzma -e1 >/dev/null 2>&1 || echo "BILGI: perl LZMA modulu yok (7z hash cikarma calismaz)"

if [[ ! -f "$PROJE/filecracker.py" ]]; then
  echo "HATA: gomulu program cozulemedi."
  exit 1
fi
echo "Kaynak: gomulu paket"

# ---- dosyalar ----
$SUDO install -Dm755 "$PROJE/filecracker.py" "$LIB/filecracker.py"
$SUDO install -Dm644 "$PROJE/common-passwords.txt" "$LIB/common-passwords.txt"
$SUDO install -Dm644 "$PROJE/filecracker.svg" /usr/share/icons/hicolor/scalable/apps/filecracker.svg
$SUDO install -Dm644 "$PROJE/filecracker.desktop" /usr/share/applications/filecracker.desktop
printf '#!/bin/sh\nexec python3 /usr/lib/filecracker/filecracker.py "$@"\n' | $SUDO tee "$BIN" >/dev/null
$SUDO chmod 755 "$BIN"
$SUDO ln -sf filecracker /usr/bin/filecracker-gpu || true
$SUDO ln -sf filecracker /usr/bin/pdfcracker || true

# ---- masaustu kisayolu ----
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
echo "Bitti. Calistir: filecracker  (menude: File Cracker)"
echo "GPU: hashcat buldugu TUM kartlari kullanir (NVIDIA + AMD + Intel). GPU'n zayifsa pencerede 'CPU Crack' sec."
exit 0
__PAYLOAD__
