# Maintainer: utku
pkgname=filecracker-gpu
pkgver=2.0.0
pkgrel=1
pkgdesc="One-click document+archive password recovery: PDF, Office, ODT, ZIP, RAR, 7Z, KDBX on ALL GPUs (hashcat)"
arch=('any')
url="https://github.com/USERNAME/filecracker-gpu"
license=('MIT')
depends=('python-pyqt6' 'hashcat' 'john' 'qpdf')
optdepends=('pdfrip: CPU fallback for PDF date and brute-force attacks'
            'p7zip: create/verify 7Z and ZIP archives'
            'unrar: verify RAR archives'
            'perl-compress-raw-lzma: required by 7z2john for 7Z hashes (AUR)'
            'rockyou: large wordlist for tougher passwords')
provides=('pdfcracker')
conflicts=('pdfcracker')
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP')  # run `updpkgsums` after pushing the tag

package() {
  cd "$pkgname-$pkgver"
  install -Dm755 filecracker.py "$pkgdir/usr/lib/filecracker-gpu/filecracker.py"
  install -Dm644 common-passwords.txt "$pkgdir/usr/lib/filecracker-gpu/common-passwords.txt"
  install -Dm644 filecracker.svg "$pkgdir/usr/share/icons/hicolor/scalable/apps/filecracker-gpu.svg"
  install -Dm644 filecracker.desktop "$pkgdir/usr/share/applications/filecracker-gpu.desktop"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
  install -dm755 "$pkgdir/usr/bin"
  printf '#!/bin/sh\nexec python3 /usr/lib/filecracker-gpu/filecracker.py "$@"\n' > "$pkgdir/usr/bin/filecracker-gpu"
  chmod 755 "$pkgdir/usr/bin/filecracker-gpu"
  # backward compat with v1
  ln -s filecracker-gpu "$pkgdir/usr/bin/pdfcracker"
}
