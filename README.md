# File Cracker (GPU)

Tek tıkla evrensel şifre kurtarma aracı. **Tüm GPU'ları** kullanır (NVIDIA + AMD + Intel, hashcat'e `-d` kısıtı verilmez).

One-click universal password recovery. Uses **ALL GPUs** (NVIDIA + AMD + Intel, no `-d` limit to hashcat).

## Desteklenen dosyalar / Supported files

| Tür | Uzantılar | Hash çıkarıcı | hashcat modu |
|---|---|---|---|
| PDF | `.pdf` | `pdf2john` + `qpdf` anında kilit açma + `pdfrip` CPU yedeği | 10400, 10500, 10600, 10700 |
| Office (modern) | `.docx .xlsx .pptx .docm .xlsm .pptm` | `office2john` | 9400, 9500, 9600 |
| Office (eski) | `.doc .xls .ppt` | `office2john` | 9700, 9800 ailesi |
| LibreOffice | `.odt .ods .odp` | `libreoffice2john` | 18400, 18600 |
| ZIP | `.zip` | `zip2john` | 13600 (WinZip AES), 17200 ailesi (PKZIP) |
| RAR | `.rar` | `rar2john` | 13000 (RAR5), 12500/23700/23800 (RAR3) |
| 7-Zip | `.7z` | `7z2john` | 11600 |
| KeePass | `.kdbx` | `keepass2john` | 13400, 34300 |
| iWork | `.pages .numbers .key` | `iwork2john` | 23300 |

## Mantık (eski PDF Cracker ile aynı)

1. **Instant unlock (sadece PDF):** `qpdf --decrypt` ile baskı/kısıt kilidi ~0.01 sn'de kalkar.
2. **GPU crack:** `*2john` ile hash çıkar → `hashcat` **tüm kartlarla** dener:
   yaygın şifreler → 4/6/8 hane sayı → kısa alfanümerik (1-4).
3. **CPU yedeği (PDF):** `pdfrip` boş şifre + tarih kalıpları.

Not: AES-256 (PDF 10700, 7z 11600, RAR5 13000, Office 2013+) gerçekte **yavaştır**;
bilinmeyen güçlü şifre saatler/günler sürebilir. Bu normaldir.

## Motor seçimi (pencerede)

| Motor | Ne yapar | Kimin için |
|---|---|---|
| Auto | Önce GPU, bulamazsa CPU yedeği | Önerilen |
| GPU Crack | Sadece `hashcat` (tüm GPU'lar) | Güçlü ekran kartı olanlar |
| CPU Crack | Sadece `john` (+ PDF'te `pdfrip`) | GPU'su zayıf / GPU'suzlar |
| Instant Unlock | `qpdf --decrypt` (~0.01 sn) | Sadece PDF kısıt kilidi |

## Kurulum

### Tek dosya kurulum (tüm Linux, Masaüstü)

Masaüstündeki `filecracker-kur.sh` Arch/CachyOS, Debian/Ubuntu,
Fedora ve openSUSE'yi otomatik tanır:

```bash
bash ~/Masaüstü/filecracker-kur.sh
```

### Arch / CachyOS (AUR)

```bash
yay -S filecracker
filecracker
```

Eski `pdfcracker` paketiyle çakışır (yerine geçer); `pdfcracker` komutu simlink olarak kalır.

## Tek dosya kurulum (Masaüstü)

Masaüstündeki `filecracker-kur.sh` tek dosyadır: bağımlılıkları kurar,
uygulamayı, simgeyi ve kısayolu yükler.

```bash
bash ~/Masaüstü/filecracker-kur.sh
```

## Gereksinimler

- `python-pyqt6`, `hashcat`, `john` (tüm `*2john` araçları), `qpdf`
- İsteğe bağlı: `pdfrip` (PDF CPU yedeği), `p7zip` + `unrar` (arşiv doğrulama),
  `perl-compress-raw-lzma` (AUR, `7z2john` için), `rockyou` wordlist
- GPU: NVIDIA (CUDA) / AMD (ROCm/OpenCL) / Intel (OpenCL) — hashcat bulduğu
  her cihazı otomatik kullanır, ayar gerekmez.

## Dosyalar

- `filecracker.py` — uygulamanın tamamı (PyQt6)
- `filecracker.svg` — simge (PDF + DOC + ZIP + açık kilit + GPU şimşeği)
- `filecracker.desktop` — menü/kısayol girdisi
- `common-passwords.txt` — dahili wordlist

## Test (2x RTX 3090, Auto ve CPU modlarında 5/5)

| Dosya | Auto | CPU |
|---|---|---|
| PDF (AES-256) | GPU 10700 | john PDF |
| DOCX (Office 2013) | GPU 9600 | john Office |
| ZIP (PKZIP) | john PKZIP (GPU bulamaz, john anında) | john PKZIP |
| RAR5 | GPU 13000 | john RAR5 |
| 7Z | GPU 11600 | john 7z |

## Lisans

MIT
