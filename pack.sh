#!/bin/bash
# filecracker .deb + .rpm paketlerini uretir
# Kullanim: bash pack.sh   (cikti: dist/)
set -e
VER=2.0.0
REL=1
SRC="$(cd "$(dirname "$0")" && pwd)"
DIST="$SRC/dist"
rm -rf "$DIST" /tmp/fc-deb /tmp/fc-rpmbuild
mkdir -p "$DIST"

echo "== .deb =="
D=/tmp/fc-deb
mkdir -p "$D/DEBIAN" "$D/usr/lib/filecracker" "$D/usr/bin" \
  "$D/usr/share/icons/hicolor/scalable/apps" "$D/usr/share/applications" \
  "$D/usr/share/doc/filecracker"
cp "$SRC/filecracker.py" "$SRC/common-passwords.txt" "$D/usr/lib/filecracker/"
cp "$SRC/filecracker.svg" "$D/usr/share/icons/hicolor/scalable/apps/filecracker.svg"
cp "$SRC/filecracker.desktop" "$D/usr/share/applications/"
cp "$SRC/README.md" "$D/usr/share/doc/filecracker/"
cp "$SRC/LICENSE" "$D/usr/share/doc/filecracker/copyright"
printf '#!/bin/sh\nexec python3 /usr/lib/filecracker/filecracker.py "$@"\n' > "$D/usr/bin/filecracker"
chmod 755 "$D/usr/bin/filecracker" "$D/usr/lib/filecracker/filecracker.py"
ln -s filecracker "$D/usr/bin/pdfcracker"
cat > "$D/DEBIAN/control" <<EOF
Package: filecracker
Version: $VER
Architecture: all
Maintainer: Utku92
Depends: python3-pyqt6 | python3-qt6, hashcat, john, qpdf
Suggests: p7zip-full, unrar, libcompress-raw-lzma-perl
Section: utils
Priority: optional
Description: Document and archive password recovery on all GPUs
 One-click password recovery for PDF, Office, LibreOffice, ZIP, RAR,
 7Z, KeePass and iWork files. Uses hashcat on ALL GPUs
 (NVIDIA + AMD + Intel) with john CPU fallback.
Conflicts: pdfcracker, filecracker-gpu
Replaces: pdfcracker, filecracker-gpu
EOF
cat > "$D/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
#DEBHELPER#
exit 0
EOF
chmod 755 "$D/DEBIAN/postinst"
dpkg-deb --root-owner-group --build "$D" "$DIST/filecracker_${VER}_all.deb"
echo "deb ok: $(du -h "$DIST/filecracker_${VER}_all.deb" | cut -f1)"

echo "== .rpm =="
R=/tmp/fc-rpmbuild
mkdir -p "$R"/{BUILD,RPMS,SRPMS,SOURCES,SPECS}
tar -czf "$R/SOURCES/filecracker-$VER.tar.gz" -C "$SRC" \
  filecracker.py common-passwords.txt filecracker.svg filecracker.desktop README.md LICENSE
cat > "$R/SPECS/filecracker.spec" <<EOF
Name:           filecracker
Version:        $VER
Release:        $REL%{?dist}
Summary:        Document and archive password recovery on all GPUs
License:        MIT
URL:            https://github.com/Utku92/filecracker
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
Requires:       python3-qt6, hashcat, john, qpdf
Suggests:       p7zip, unrar, perl-Compress-Raw-Lzma
Conflicts:      pdfcracker, filecracker-gpu
Provides:       pdfcracker = %{version}, filecracker-gpu = %{version}

%description
One-click password recovery for PDF, Office, LibreOffice, ZIP, RAR,
7Z, KeePass and iWork files. Uses hashcat on ALL GPUs
(NVIDIA + AMD + Intel) with john CPU fallback.

%prep
%setup -q -c -T
tar -xzf %{SOURCE0}

%install
install -Dm755 filecracker.py %{buildroot}%{_libdir}/filecracker/filecracker.py
install -Dm644 common-passwords.txt %{buildroot}%{_libdir}/filecracker/common-passwords.txt
install -Dm644 filecracker.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/filecracker.svg
install -Dm644 filecracker.desktop %{buildroot}%{_datadir}/applications/filecracker.desktop
install -Dm644 LICENSE %{buildroot}%{_licensedir}/%{name}/LICENSE
install -Dm644 README.md %{buildroot}%{_docdir}/%{name}/README.md
mkdir -p %{buildroot}%{_bindir}
printf '#!/bin/sh\\nexec python3 %{_libdir}/filecracker/filecracker.py "\$@"\\n' > %{buildroot}%{_bindir}/filecracker
chmod 755 %{buildroot}%{_bindir}/filecracker
ln -s filecracker %{buildroot}%{_bindir}/pdfcracker

%post
update-desktop-database %{_datadir}/applications >/dev/null 2>&1 || true
gtk-update-icon-cache -f %{_datadir}/icons/hicolor >/dev/null 2>&1 || true
exit 0

%files
%{_libdir}/filecracker/
%{_bindir}/filecracker
%{_bindir}/pdfcracker
%{_datadir}/icons/hicolor/scalable/apps/filecracker.svg
%{_datadir}/applications/filecracker.desktop
%license %{_licensedir}/%{name}/LICENSE
%doc %{_docdir}/%{name}/README.md

%changelog
* Fri Oct 16 2026 Utku92 - 2.0.0-1
- PDF+Office+ODT+ZIP+RAR+7Z+KDBX, all-GPU hashcat, CPU/GPU engine select
EOF
rpmbuild --define "_topdir $R" -bb "$R/SPECS/filecracker.spec" >/tmp/fc-rpm.log 2>&1 || { tail -20 /tmp/fc-rpm.log; exit 1; }
find "$R/RPMS" -name "*.rpm" -exec cp {} "$DIST/" \;
echo "rpm ok: $(du -h "$DIST"/*.rpm | cut -f1)"
echo "== tek dosya kurulum (gomulu) =="
cp "$SRC/setup-template.sh" "$DIST/filecracker-kur.sh"
tar -czf - -C "$SRC" filecracker.py common-passwords.txt filecracker.svg filecracker.desktop | base64 >> "$DIST/filecracker-kur.sh"
chmod +x "$DIST/filecracker-kur.sh"
echo "setup ok: $(du -h "$DIST/filecracker-kur.sh" | cut -f1)"
rm -rf /tmp/fc-deb /tmp/fc-rpmbuild
echo "== dist =="; ls -la "$DIST"
