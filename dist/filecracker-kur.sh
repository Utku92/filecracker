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

# ---- eski v1 (filecracker-gpu) kalintilarini temizle ----
$SUDO rm -rf /usr/lib/filecracker-gpu \
  /usr/share/applications/filecracker-gpu.desktop \
  /usr/share/icons/hicolor/scalable/apps/filecracker-gpu.svg \
  "$HOME/Masaüstü/filecracker-gpu.desktop" "$HOME/Desktop/filecracker-gpu.desktop" 2>/dev/null || true

# ---- dosyalar ----
if pacman -Q filecracker >/dev/null 2>&1; then
  echo "AUR paketi zaten kurulu -> dosyalari ezmiyorum (db tutarli kalir)."
else
$SUDO install -Dm755 "$PROJE/filecracker.py" "$LIB/filecracker.py"
$SUDO install -Dm644 "$PROJE/common-passwords.txt" "$LIB/common-passwords.txt"
$SUDO install -Dm644 "$PROJE/filecracker.svg" /usr/share/icons/hicolor/scalable/apps/filecracker.svg
$SUDO install -Dm644 "$PROJE/filecracker.desktop" /usr/share/applications/filecracker.desktop
printf '#!/bin/sh\nexec python3 /usr/lib/filecracker/filecracker.py "$@"\n' | $SUDO tee "$BIN" >/dev/null
$SUDO chmod 755 "$BIN"
$SUDO ln -sf filecracker /usr/bin/filecracker-gpu || true
$SUDO ln -sf filecracker /usr/bin/pdfcracker || true
fi

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
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
