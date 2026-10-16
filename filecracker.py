#!/usr/bin/env python3
# File Cracker (GPU) - one-click universal password tool, uses ALL GPUs
# Supports: PDF, Office (docx/xlsx/pptx/doc/xls/ppt...), LibreOffice (odt/ods/odp),
#           ZIP, RAR, 7Z, KeePass KDBX, Apple iWork
# Chain: *2john -> hashcat on ALL GPUs (NVIDIA/AMD/Intel, no -d limit) -> CPU fallback
# Usage: python3 filecracker.py [file]
import os
import re
import shutil
import subprocess
import sys

from PyQt6.QtCore import Qt, QThread, pyqtSignal
from PyQt6.QtGui import QFont, QIcon
from PyQt6.QtWidgets import (
    QApplication, QComboBox, QFileDialog, QHBoxLayout, QLabel, QMainWindow,
    QMessageBox, QPlainTextEdit, QPushButton, QVBoxLayout, QWidget,
)

# ---- external tools ----
PDFRIP = shutil.which("pdfrip") or "/usr/bin/pdfrip"
PDF2JOHN = shutil.which("pdf2john") or "/usr/bin/pdf2john"
OFFICE2JOHN = shutil.which("office2john") or "/usr/bin/office2john"
LIBRE2JOHN = shutil.which("libreoffice2john") or "/usr/bin/libreoffice2john"
ZIP2JOHN = shutil.which("zip2john") or "/usr/bin/zip2john"
RAR2JOHN = shutil.which("rar2john") or "/usr/bin/rar2john"
SEVENZ2JOHN = shutil.which("7z2john") or "/usr/bin/7z2john"
KEEPASS2JOHN = shutil.which("keepass2john") or "/usr/bin/keepass2john"
IWORK2JOHN = shutil.which("iwork2john") or "/usr/bin/iwork2john"
HASHCAT = shutil.which("hashcat") or "/usr/bin/hashcat"
QPDF = shutil.which("qpdf") or "/usr/bin/qpdf"
SEVENZ = shutil.which("7z") or shutil.which("7zz") or "/usr/bin/7z"
UNRAR = shutil.which("unrar") or "/usr/bin/unrar"

APP_NAME = "File Cracker"

COMMON_PASSWORDS = """123456
123456789
12345678
1234
12345
0000
000000
1111
111111
1212
7777
5555
9999
123123
123321
654321
987654
password
Password1
password123
qwerty
abc123
1q2w3e
letmein
welcome
admin
admin123
test123
testing
testing123
secret123
document123
pdf123
zip123
rar123
arsiv123
istanbul
Istanbul34
Istanbul34
ankara
Ankara06
izmir
turkiye
Turkiye123
Malatya44
2020
2021
2022
2023
2024
2025
01012000
01011990
1234qwer
qwer1234
asdasd
"""

# extension -> kind
EXT_KIND = {
    ".pdf": "pdf",
    ".docx": "office", ".xlsx": "office", ".pptx": "office",
    ".docm": "office", ".xlsm": "office", ".pptm": "office",
    ".dotx": "office", ".xltx": "office", ".potx": "office",
    ".doc": "office", ".xls": "office", ".ppt": "office",
    ".pps": "office", ".ppsx": "office",
    ".odt": "odf", ".ods": "odf", ".odp": "odf", ".odg": "odf",
    ".zip": "zip", ".cbz": "zip",
    ".rar": "rar", ".cbr": "rar",
    ".7z": "7z", ".cb7": "7z",
    ".kdbx": "keepass",
    ".pages": "iwork", ".numbers": "iwork", ".key": "iwork",
}

FILE_FILTER = (
    "All supported ("
    "*.pdf *.docx *.xlsx *.pptx *.docm *.xlsm *.pptm "
    "*.doc *.xls *.ppt *.odt *.ods *.odp *.zip *.rar *.7z *.kdbx"
    ");;PDF (*.pdf);;Office (*.docx *.xlsx *.pptx *.docm *.xlsm *.pptm *.doc *.xls *.ppt);;"
    "LibreOffice (*.odt *.ods *.odp);;Archives (*.zip *.rar *.7z);;KeePass (*.kdbx);;All files (*)"
)

SUCCESS_RE = re.compile(r'Success:\s+found\s+\w+\s+password\s+"(.*)"\.', re.IGNORECASE)
# known hash prefixes emitted by *2john tools
HASH_PREFIXES = ("$pdf$", "$office$", "$oldoffice$", "$odf$",
                 "$pkzip$", "$pkzip2$", "$zip2$", "$zip$", "$rar3$", "$rar5$",
                 "$7z$", "$keepass$", "$iwork$", "$sha1$")

# john --format names per file kind (CPU fallback when GPU finds nothing)
JOHN_FORMATS = {
    "pdf": ["PDF"],
    "office": ["Office", "oldoffice"],
    "odf": ["ODF"],
    "zip": ["PKZIP"],
    "rar": ["RAR5", "rar"],
    "7z": ["7z"],
    "keepass": ["KeePass"],
    "iwork": ["iwork"],
}

# shim for *2john python scripts broken on Python >= 3.14
# (ElementTree.getiterator was removed; john ships old code)
PY_SHIM = (
    "import sys,runpy,xml.etree.ElementTree as ET;"
    "ET.ElementTree.getiterator=(lambda s,*a,**k:s.iter(*a,**k));"
    "sys.argv=%r;runpy.run_path(%r,run_name='__main__')"
)


def run_2john(cmd):
    """Run a *2john extractor; retry via shim if it hits the getiterator bug."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except Exception as e:
        return None, str(e)
    err = (r.stderr or "") + (r.stdout or "")
    if "getiterator" in err:
        tool = shutil.which(cmd[0]) or cmd[0]
        try:
            shim = ["python3", "-c", PY_SHIM % (cmd, tool)]
            r2 = subprocess.run(shim, capture_output=True, text=True, timeout=120)
            return r2, ""
        except Exception as e:
            return None, str(e)
    return r, ""


def app_icon():
    """Window top-left icon: installed icon, else the svg next to the project."""
    base = os.path.dirname(os.path.abspath(__file__))
    for p in ("/usr/share/icons/hicolor/scalable/apps/filecracker.svg",
              os.path.join(base, "filecracker.svg")):
        if os.path.isfile(p):
            return QIcon(p)
    return QIcon()


def ensure_wordlist():
    base = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(base, "common-passwords.txt")
    if not os.path.exists(path):
        with open(path, "w", encoding="utf-8") as f:
            f.write(COMMON_PASSWORDS)
    return path


def gpu_names():
    """List ALL GPUs from every vendor (NVIDIA/AMD/Intel) + hashcat backends.

    hashcat itself uses every device it finds unless -d is given;
    we never pass -d, so this is informational only.
    """
    gpus = []
    # NVIDIA
    try:
        out = subprocess.run(["nvidia-smi", "-L"], capture_output=True, text=True, timeout=10)
        if out.returncode == 0 and out.stdout.strip():
            gpus += [l.strip() for l in out.stdout.strip().splitlines()]
    except Exception:
        pass
    # AMD (new + legacy tools)
    for tool in (["amd-smi", "list"], ["rocm-smi", "--showproductname"]):
        try:
            out = subprocess.run(tool, capture_output=True, text=True, timeout=10)
            if out.returncode == 0 and out.stdout.strip():
                for line in out.stdout.strip().splitlines():
                    s = line.strip()
                    if s and "===" not in s and "GPU" in s or "AMD" in s or "Radeon" in s:
                        gpus.append(f"[AMD] {s}")
                break
        except Exception:
            continue
    # Intel
    for tool in (["intel-smi", "-L"], ["intel_gpu_top", "-l"]):
        try:
            out = subprocess.run(tool, capture_output=True, text=True, timeout=10)
            if out.returncode == 0 and out.stdout.strip():
                gpus.append("[Intel] " + out.stdout.strip().splitlines()[0][:100])
                break
        except Exception:
            continue
    # hashcat backend count (covers NVIDIA/CUDA, AMD/HIP, Intel/OpenCL at once)
    try:
        out = subprocess.run([HASHCAT, "-I"], capture_output=True, text=True, timeout=30)
        txt = (out.stdout or "") + (out.stderr or "")
        n = txt.count("Backend Device ID")
        if n and not gpus:
            gpus.append(f"{n} device(s) reported by hashcat -I")
        elif n:
            gpus.append(f"hashcat sees {n} backend device(s) - all will be used")
    except Exception:
        pass
    # lspci fallback
    if not gpus:
        try:
            out = subprocess.run(["lspci"], capture_output=True, text=True, timeout=10)
            for line in (out.stdout or "").splitlines():
                if any(k in line for k in ("VGA", "3D controller", "Display controller")):
                    gpus.append(line.split(": ", 1)[-1].strip()[:100])
        except Exception:
            pass
    return gpus


def file_kind(path):
    ext = os.path.splitext(path)[1].lower()
    return EXT_KIND.get(ext, "unknown")


def detect_pdf_modes(hash_str):
    """$pdf$V*R*bits... -> hashcat modes to try."""
    try:
        parts = hash_str.strip().split("*")
        v = int(parts[0].replace("$pdf$", ""))
        r = int(parts[1])
    except Exception:
        return [10500, 10400, 10600, 10700]
    if v == 1 and r == 2:
        return [10400]
    if v == 1 and r == 3:
        return [10510, 10500]
    if v == 2 and r == 3:
        return [10500]
    if v == 4:
        return [10600]
    if v == 5 and r == 5:
        return [10600, 10700]
    if v == 5 and r == 6:
        return [10700]
    return [10500, 10400, 10600, 10700]


def modes_for_hash(h):
    """Map a *2john hash blob to hashcat modes."""
    if h.startswith("$pdf$"):
        return detect_pdf_modes(h)
    if h.startswith("$office$"):
        # $office$*year*ver*spin*keylen*salt*...  year decides mode
        try:
            year = h.split("*")[1]
            if "2007" in year:
                return [9400]
            if "2010" in year:
                return [9500]
            if "2013" in year:
                return [9600]
        except Exception:
            pass
        # 2016+ AES-256-SHA512 is NOT in hashcat (falls back to john); still try 9600 family
        return [9600, 9500, 9400]
    if h.startswith("$oldoffice$"):
        # $oldoffice$0/1 -> MD5+RC4 (9700 family), $oldoffice$3/4 -> SHA1+RC4 (9800 family)
        try:
            typ = h.split("*")[1]
            if typ in ("0", "1"):
                return [9700, 9710, 9720]
            return [9800, 9810, 9820]
        except Exception:
            return [9700, 9800]
    if h.startswith("$odf$"):
        return [18400, 18600]
    if h.startswith("$zip2$"):
        return [13600]  # WinZip AES
    if h.startswith("$pkzip2$") or h.startswith("$pkzip$") or h.startswith("$zip$"):
        return [17200, 17210, 17220, 17225, 17230]
    if h.startswith("$rar5$"):
        return [13000]
    if h.startswith("$rar3$"):
        return [12500, 23700, 23800]
    if h.startswith("$7z$"):
        return [11600]
    if h.startswith("$keepass$"):
        return [13400, 34300]
    if h.startswith("$iwork$"):
        return [23300]
    return []


def extract_blob(stdout):
    """Pull hash blob(s) out of *2john output.

    Returns (blobs, raw_lines): blobs have the 'filename:' prefix stripped
    (for hashcat), raw_lines keep the original full lines (for john,
    which requires the filename prefix for formats like PKZIP).
    """
    hashes, raws = [], []
    for line in (stdout or "").splitlines():
        line = line.strip()
        if not line:
            continue
        idx = -1
        for p in HASH_PREFIXES:
            i = line.find(p)
            if i != -1:
                idx = i
                break
        if idx != -1:
            hashes.append(line[idx:].strip())
            raws.append(line)
    # dedupe, keep order
    seen, out, rout = set(), [], []
    for h, r in zip(hashes, raws):
        if h not in seen:
            seen.add(h)
            out.append(h)
            rout.append(r)
    return out, rout


class CrackWorker(QThread):
    line = pyqtSignal(str)
    step = pyqtSignal(str)
    finished_ok = pyqtSignal(str, str)
    finished_fail = pyqtSignal(str)

    def __init__(self, target_path, mode="auto", wordlist=""):
        super().__init__()
        self.target_path = target_path
        self.mode = mode  # "auto" | "instant" | "gpu" | "cpu"
        self.custom_wordlist = wordlist
        self._stop = False
        self.proc = None
        self.session = f"filecracker-{os.getpid()}"
        self.kind = file_kind(target_path)

    def stop(self):
        self._stop = True
        if self.proc and self.proc.poll() is None:
            try:
                self.proc.terminate()
            except Exception:
                pass

    def run_proc(self, title, cmd):
        if self._stop:
            return None
        self.step.emit(title)
        self.line.emit(f"\n=== {title} ===\n$ {' '.join(cmd)}\n")
        try:
            self.proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1,
            )
        except FileNotFoundError as e:
            self.line.emit(f"ERROR: {e}")
            return False
        output = []
        try:
            for raw in self.proc.stdout:
                if self._stop:
                    try:
                        self.proc.terminate()
                    except Exception:
                        pass
                    return None
                output.append(raw)
                s = raw.rstrip("\n")
                if any(k in s for k in ("Speed.#", "Recovered", "Progress", "Success",
                                        "Exhausted", "Cracked", "Status", "Guess.",
                                        "Candidates.", "No hashes", "Separator",
                                        "Already an instance", "ATTENTION",
                                        "found user", "found owner", "Attempts")):
                    self.line.emit(s)
                elif len(s) < 300:
                    # keep 2john errors visible (they are short)
                    if any(k in s.lower() for k in ("error", "not encrypted", "no hash",
                                                    "failed", "can't", "warning")):
                        self.line.emit(s)
        finally:
            try:
                self.proc.wait(timeout=10)
            except Exception:
                pass
        return "".join(output)

    def hashcat_show(self, mode, hashfile, potfile):
        try:
            out = subprocess.run(
                [HASHCAT, "-m", str(mode), hashfile, "--show",
                 "--potfile-path", potfile],
                capture_output=True, text=True, timeout=30)
            txt = (out.stdout or "").strip()
            if txt:
                pw = txt.splitlines()[0].rsplit(":", 1)[-1]
                return decode_hex_pass(pw)
        except Exception as e:
            self.line.emit(f"--show error: {e}")
        return None

    def gpu_step(self, title, mode, hashfile, potfile, attack_args):
        # NOTE: no -d flag -> hashcat uses ALL GPUs (NVIDIA + AMD + Intel).
        out = self.run_proc(
            title,
            [HASHCAT, "-m", str(mode), hashfile,
             "--session", self.session,
             "-O", "-w", "4", "--status", "--status-timer", "2",
             "--potfile-path", potfile] + attack_args)
        if out is None:
            return None
        if "Already an instance" in out:
            return "BUSY"
        if "No hashes loaded" in out or "Separator unmatched" in out:
            return "BADMODE"
        pw = self.hashcat_show(mode, hashfile, potfile)
        if pw is not None:
            return pw
        return False

    def cpu_step_pdfrip(self, title, args):
        out = self.run_proc(title, [PDFRIP] + args)
        if out is None:
            return None
        m = SUCCESS_RE.search(out)
        if m:
            return m.group(1)
        return False

    def john_step(self, title, hashfile, wordlist, fmt=None):
        """CPU fallback with John the Ripper (handles PKZIP etc. where GPU fails)."""
        cmd = ["john", f"--wordlist={wordlist}"]
        if fmt:
            cmd.append(f"--format={fmt}")
        cmd.append(hashfile)
        out = self.run_proc(title, cmd)
        if out is None:
            return None
        show = ["john", "--show"]
        if fmt:
            show.append(f"--format={fmt}")
        show.append(hashfile)
        try:
            r = subprocess.run(show, capture_output=True, text=True, timeout=30)
            for line in (r.stdout or "").splitlines():
                if ":" in line and "password hash cracked" not in line and "Session completed" not in line:
                    parts = line.split(":")
                    if len(parts) >= 2 and parts[1] not in ("", "?", "No password hashes loaded"):
                        # john --show: file:password:rest... (password rarely has ':')
                        pw = parts[1]
                        if pw and not pw.startswith(" "):
                            return pw
        except Exception as e:
            self.line.emit(f"john --show error: {e}")
        return False

    def instant_unlock_pdf(self, pdf):
        if not os.path.exists(QPDF):
            self.line.emit("qpdf not installed, skipping instant unlock.")
            return None
        out = os.path.join(os.path.dirname(os.path.abspath(pdf)),
                           os.path.splitext(os.path.basename(pdf))[0] + "-unlocked.pdf")
        self.step.emit("Instant unlock (no cracking)...")
        self.line.emit("\n=== Instant unlock (no cracking) ===\n$ qpdf --decrypt --password=\"\" ...\n")
        try:
            r = subprocess.run([QPDF, "--decrypt", "--password=", pdf, out],
                               capture_output=True, text=True, timeout=120)
        except Exception as e:
            self.line.emit(f"qpdf error: {e}")
            return None
        if r.returncode == 0 and os.path.isfile(out):
            return out
        err = ((r.stderr or "") + (r.stdout or "")).strip().splitlines()
        msg = err[-1] if err else ""
        if "invalid password" in msg.lower():
            self.line.emit("Real open password set - instant unlock impossible, GPU cracking starts.")
            return None
        self.line.emit(f"qpdf: {msg}")
        return None

    # ---- hash extraction per kind ----
    def extract_hash(self, path):
        kind = self.kind
        cands = []  # (tool, args)
        if kind == "pdf":
            cands = [("pdf2john", [PDF2JOHN, path])]
        elif kind == "office":
            cands = [("office2john", [OFFICE2JOHN, path])]
        elif kind == "odf":
            cands = [("libreoffice2john", [LIBRE2JOHN, path]),
                     ("office2john", [OFFICE2JOHN, path])]
        elif kind == "zip":
            cands = [("zip2john", [ZIP2JOHN, path])]
        elif kind == "rar":
            cands = [("rar2john", [RAR2JOHN, path])]
        elif kind == "7z":
            cands = [("7z2john", [SEVENZ2JOHN, path])]
        elif kind == "keepass":
            cands = [("keepass2john", [KEEPASS2JOHN, path])]
        elif kind == "iwork":
            cands = [("iwork2john", [IWORK2JOHN, path])]
        else:
            # unknown extension: try every extractor
            cands = [("pdf2john", [PDF2JOHN, path]),
                     ("office2john", [OFFICE2JOHN, path]),
                     ("libreoffice2john", [LIBRE2JOHN, path]),
                     ("zip2john", [ZIP2JOHN, path]),
                     ("rar2john", [RAR2JOHN, path]),
                     ("7z2john", [SEVENZ2JOHN, path])]

        last_err = ""
        for name, cmd in cands:
            if not os.path.exists(cmd[0]):
                continue
            self.step.emit(f"Extracting hash ({name})...")
            self.line.emit(f"$ {' '.join(cmd)}")
            r, run_err = run_2john(cmd)
            if r is None:
                last_err = run_err
                continue
            blobs, raws = extract_blob((r.stdout or "") + "\n" + (r.stderr or ""))
            if blobs:
                modes = []
                for b in blobs:
                    modes += modes_for_hash(b)
                # dedupe modes, keep order
                seen, uniq = set(), []
                for m in modes:
                    if m not in seen:
                        seen.add(m)
                        uniq.append(m)
                if not uniq:
                    # hash found but unknown prefix -> let hashcat autodetect (no -m)
                    uniq = [0]
                self.line.emit(f"Hash extracted via {name} ({len(blobs[0])} chars): {blobs[0][:70]}...")
                self.line.emit(f"hashcat modes to try: {uniq}")
                return blobs, raws, uniq, name
            err = ((r.stderr or "") + (r.stdout or "")).strip()
            if "Compress::Raw::Lzma" in err or "Compress/Raw/Lzma" in err:
                self.line.emit(
                    "7z2john needs the Perl LZMA module. Install it once:\n"
                    "  yay -S perl-compress-raw-lzma   (AUR)\n"
                    "or: sudo cpan Compress::Raw::Lzma")
                last_err = "missing perl Compress::Raw::Lzma"
                continue
            if err:
                last_err = err.splitlines()[-1][:300] if err.splitlines() else err[:300]
        return None, [], [], last_err or "no extractor produced a hash"

    def verify_archive(self, path, password):
        """Quick check that the password actually opens the archive."""
        kind = self.kind
        try:
            if kind == "zip":
                if os.path.exists(SEVENZ):
                    r = subprocess.run([SEVENZ, "l", f"-p{password}", path],
                                       capture_output=True, text=True, timeout=60)
                    if r.returncode == 0:
                        return True
                r = subprocess.run(["unzip", "-l", "-P", password, path],
                                   capture_output=True, text=True, timeout=60)
                return r.returncode == 0
            if kind == "rar":
                for cmd in ([UNRAR] if os.path.exists(UNRAR) else [],
                            ["rar"] if shutil.which("rar") else []):
                    try:
                        r = subprocess.run(cmd + ["l", f"-p{password}", path],
                                           capture_output=True, text=True, timeout=60)
                        if r.returncode == 0:
                            return True
                    except Exception:
                        continue
                if os.path.exists(SEVENZ):
                    try:
                        r = subprocess.run([SEVENZ, "l", f"-p{password}", path],
                                           capture_output=True, text=True, timeout=60)
                        return r.returncode == 0
                    except Exception:
                        pass
                return None
            if kind == "7z" and os.path.exists(SEVENZ):
                r = subprocess.run([SEVENZ, "l", f"-p{password}", path],
                                   capture_output=True, text=True, timeout=60)
                return r.returncode == 0
        except Exception:
            pass
        return None  # unknown -> skip verification

    def save_unlocked_pdf(self, pdf, password):
        out = os.path.join(os.path.dirname(os.path.abspath(pdf)),
                           os.path.splitext(os.path.basename(pdf))[0] + "-unlocked.pdf")
        if not os.path.exists(QPDF):
            return ""
        try:
            r = subprocess.run([QPDF, "--decrypt", f"--password={password}", pdf, out],
                               capture_output=True, text=True, timeout=180)
            if r.returncode == 0 and os.path.isfile(out):
                return out
        except Exception:
            pass
        return ""

    def run(self):
        path = self.target_path
        if not os.path.isfile(path):
            self.finished_fail.emit("File not found.")
            return
        if not os.path.exists(HASHCAT):
            self.finished_fail.emit("hashcat is not installed.")
            return

        # Instant unlock for PDFs (restriction-only files, ~0.01s)
        if self.kind == "pdf" and self.mode in ("auto", "instant"):
            unlocked = self.instant_unlock_pdf(path)
            if self._stop:
                self.finished_fail.emit("Stopped.")
                return
            if unlocked:
                self.finished_ok.emit(f"UNLOCKED_FILE::{unlocked}", "Instant unlock (no password needed)")
                return
            if self.mode == "instant":
                self.finished_fail.emit(
                    "Instant unlock not possible: this PDF has a real open password.\n"
                    "Use 'GPU Crack' or 'CPU Crack' to brute-force it.")
                return
        elif self.mode == "instant" and self.kind != "pdf":
            self.finished_fail.emit("Instant unlock only works for PDFs. Use GPU/CPU Crack for this file type.")
            return

        if self.mode not in ("auto", "gpu", "cpu"):
            self.finished_fail.emit("Unknown mode.")
            return
        if self.mode == "cpu" and self.kind == "pdf" and False:
            pass  # pdf cpu path shares the same john/pdfrip fallbacks below

        use_gpu = self.mode in ("auto", "gpu")
        use_cpu = self.mode in ("auto", "cpu")
        if not use_gpu:
            self.line.emit("Engine: CPU only (john + pdfrip) - GPU steps skipped.")

        gpus = gpu_names()
        if gpus:
            self.line.emit(f"GPUs ({len(gpus)}):\n" + "\n".join(gpus))
            self.line.emit("hashcat uses ALL GPUs by default (no -d restriction: NVIDIA + AMD + Intel).")
        else:
            self.line.emit("GPU list unavailable, hashcat will still use all devices it finds.")

        self.line.emit(f"File type: {self.kind} ({os.path.basename(path)})")

        blobs, raws, modes, extractor = self.extract_hash(path)
        if not blobs:
            msg = modes  # here modes var holds last_err string
            self.finished_fail.emit(
                "No hash extracted from this file.\n"
                f"Extractor output: {msg}\n"
                "The file is probably unencrypted, or uses an unsupported scheme\n"
                "(e.g. PDF certificate encryption, Office 2016+ Agile with SHA-512).")
            return
        if modes == [0]:
            self.line.emit("Unknown hash prefix - trying hashcat autodetect + john fallback.")

        base = os.path.splitext(os.path.basename(path))[0]
        workdir = f"/tmp/filecracker-{os.getpid()}"
        os.makedirs(workdir, exist_ok=True)
        hashfile = os.path.join(workdir, base + ".hash")
        johnfile = os.path.join(workdir, base + "-john.hash")
        potfile = os.path.join(workdir, base + ".pot")
        # hashcat wants $pkzip$, john wants $pkzip2$ -> keep both variants.
        # PKZIP blobs carry trailing john metadata (":file:zip::zip");
        # hashcat needs only the $pkzip$...*$/pkzip$ part.
        blobs_hc = []
        for b in blobs:
            bb = b.replace("$pkzip2$", "$pkzip$")
            if "$pkzip$" in bb:
                m = re.search(r"(\$pkzip\$.*?\$/pkzip\$)", bb)
                if m:
                    bb = m.group(1)
                else:
                    bb = bb.split()[0]
            blobs_hc.append(bb)
        with open(hashfile, "w", encoding="utf-8") as f:
            for b in blobs_hc:
                f.write(b + "\n")
        with open(johnfile, "w", encoding="utf-8") as f:
            for rline in raws:
                f.write(rline + "\n")
        if os.path.exists(potfile):
            os.remove(potfile)
        wordlist = self.custom_wordlist if self.custom_wordlist else ensure_wordlist()

        # GPU chain - fastest first, per mode (empty in CPU-only mode)
        for mode in (modes if use_gpu else []):
            if self._stop:
                self.finished_fail.emit("Stopped.")
                return
            mflag = [] if mode == 0 else ["-m", str(mode)]
            # --show needs -m; skip autodetect show trick: use mode as-is
            self.line.emit(f"\n--- GPU attempts (mode {mode}, ALL GPUs) ---")
            steps = [
                (f"GPU [{mode}] common passwords", ["-a", "0", wordlist]),
                (f"GPU [{mode}] 4-digit numbers", ["-a", "3", "?d?d?d?d"]),
                (f"GPU [{mode}] 6-digit numbers", ["-a", "3", "?d?d?d?d?d?d"]),
                (f"GPU [{mode}] 8-digit numbers/dates", ["-a", "3", "?d?d?d?d?d?d?d?d"]),
                (f"GPU [{mode}] short alpha-numeric (1-4)", ["-a", "3", "--increment",
                                                             "--increment-min", "1",
                                                             "--increment-max", "4", "?a?a?a?a"]),
            ]
            badmode = False
            for title, args in steps:
                if mode == 0:
                    # autodetect: hashcat figures out the type itself
                    cmd_extra = args
                    out = self.run_proc(
                        title,
                        [HASHCAT, hashfile,
                         "--session", self.session,
                         "-O", "-w", "4", "--status", "--status-timer", "2",
                         "--potfile-path", potfile] + cmd_extra)
                    if out is None:
                        self.finished_fail.emit("Stopped.")
                        return
                    if "Already an instance" in out:
                        self.finished_fail.emit(
                            "Another hashcat is already using the GPUs.\n"
                            "Wait for it to finish or stop it, then try again.")
                        return
                    pw = None
                    try:
                        so = subprocess.run(
                            [HASHCAT, hashfile, "--show", "--potfile-path", potfile],
                            capture_output=True, text=True, timeout=30)
                        txt = (so.stdout or "").strip()
                        if txt:
                            pw = decode_hex_pass(txt.splitlines()[0].rsplit(":", 1)[-1])
                    except Exception:
                        pass
                    if pw is not None:
                        self.report_found(path, pw, f"GPU autodetect (all cards)")
                        return
                    continue
                res = self.gpu_step(title, mode, hashfile, potfile, args)
                if res is None:
                    self.finished_fail.emit("Stopped.")
                    return
                if res == "BUSY":
                    self.finished_fail.emit(
                        "Another hashcat is already using the GPUs.\n"
                        "Wait for it to finish or stop it, then try again.")
                    return
                if res == "BADMODE":
                    self.line.emit(f"Mode {mode} does not match this file, trying next mode.")
                    badmode = True
                    break
                if res is not False:
                    self.report_found(path, res, f"GPU (all cards, mode {mode})")
                    return
            if badmode:
                continue
            # no break: try EVERY candidate mode (e.g. whole PKZIP family),
            # then fall through to the john CPU fallback below

        # CPU with John (important for PKZIP single-file etc.
        # where hashcat GPU often finds nothing but john cracks instantly).
        # In GPU-only mode this fallback is skipped.
        if use_cpu:
            if self._stop:
                self.finished_fail.emit("Stopped.")
                return
            if os.path.exists(shutil.which("john") or "/usr/bin/john"):
                fmts = JOHN_FORMATS.get(self.kind, [])
                if self.kind == "unknown":
                    fmts = ["PDF", "Office", "ODF", "PKZIP", "RAR5", "rar", "7z", "KeePass"]
                tried = set()
                for fmt in fmts:
                    if fmt in tried:
                        continue
                    tried.add(fmt)
                    self.line.emit(f"\n--- CPU fallback (john, format {fmt}) ---")
                    res = self.john_step(f"CPU john [{fmt}] wordlist", johnfile, wordlist, fmt)
                    if res is None:
                        self.finished_fail.emit("Stopped.")
                        return
                    if res is not False:
                        self.report_found(path, res, f"CPU (john {fmt})")
                        return
                # one last try without --format (autodetect)
                if fmts:
                    self.line.emit("\n--- CPU fallback (john autodetect) ---")
                    res = self.john_step("CPU john [autodetect] wordlist", johnfile, wordlist, None)
                    if res is None:
                        self.finished_fail.emit("Stopped.")
                        return
                    if res is not False:
                        self.report_found(path, res, "CPU (john)")
                        return

        # CPU fallback for PDFs (pdfrip dates + blank)
        if self._stop:
            self.finished_fail.emit("Stopped.")
            return
        if use_cpu and self.kind == "pdf" and os.path.exists(PDFRIP):
            self.line.emit("\n--- GPU found nothing, CPU fallback (pdfrip) ---")
            cpu_steps = [
                ("CPU blank password", ["--file", path, "default-query",
                                        "--min-length", "0", "--max-length", "0"]),
                ("CPU dates DDMMYYYY", ["--file", path, "date", "1950", "2030"]),
                ("CPU dates DD.MM.YYYY", ["--file", path, "date", "--format",
                                          "DD.MM.YYYY", "1950", "2030"]),
            ]
            for title, args in cpu_steps:
                res = self.cpu_step_pdfrip(title, args)
                if res is None:
                    self.finished_fail.emit("Stopped.")
                    return
                if res is not False:
                    self.report_found(path, res, "CPU fallback (pdfrip)")
                    return

        self.finished_fail.emit(
            "Automatic attempts finished, password not found.\n"
            "Next step in the terminal (uses ALL GPUs):\n"
            f"hashcat -m {modes[0]} -a 3 --increment -w 4 \"{hashfile}\" ?a?a?a?a?a?a\n"
            "or with your wordlist: hashcat -m "
            f"{modes[0]} -a 0 \"{hashfile}\" list.txt\n"
            "Tip: RockYou (zipped) helps a lot: hashcat -m "
            f"{modes[0]} -a 0 \"{hashfile}\" /usr/share/wordlists/rockyou.txt")

    def report_found(self, path, password, via):
        extra = ""
        if self.kind == "pdf":
            unlocked = self.save_unlocked_pdf(path, password)
            if unlocked:
                extra = f"\nUnlocked copy: {unlocked}"
                self.line.emit(f"Unlocked copy saved: {unlocked}")
        elif self.kind in ("zip", "rar", "7z"):
            ok = self.verify_archive(path, password)
            if ok is True:
                self.line.emit("Password verified against the archive.")
            elif ok is False:
                self.line.emit("WARNING: archive test-listing failed, password may be partial.")
        shown = "(blank password)" if password == "" else password
        self.line.emit(f"\nPassword found via {via}: {shown}{extra}")
        if extra:
            self.finished_ok.emit(f"{password}||{extra}", via)
        else:
            self.finished_ok.emit(password, via)


def decode_hex_pass(pw):
    if pw.startswith("$HEX[") and pw.endswith("]"):
        try:
            return bytes.fromhex(pw[5:-1]).decode("utf-8", errors="replace")
        except Exception:
            return pw
    return pw


class DropLabel(QLabel):
    file_dropped = pyqtSignal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAcceptDrops(True)
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.setWordWrap(True)
        self.setMinimumHeight(120)
        self.setStyleSheet(
            "QLabel { border: 2px dashed #888; border-radius: 12px; "
            "background: #2b2b2b; color: #eee; font-size: 15px; padding: 16px; }"
        )
        self.setText("Drag & drop a file here\nPDF - Office - ZIP - RAR - 7Z\nor choose a file below")

    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
        else:
            event.ignore()

    def dropEvent(self, event):
        for url in event.mimeData().urls():
            p = url.toLocalFile()
            if p and os.path.isfile(p):
                self.file_dropped.emit(p)
                return
        QMessageBox.warning(self, APP_NAME, "You did not drop a file.")


class MainWindow(QMainWindow):
    def __init__(self, start_file=""):
        super().__init__()
        self.setWindowTitle(APP_NAME)
        self.setWindowIcon(app_icon())
        self.resize(700, 640)
        self.setMinimumSize(480, 380)
        self.target_path = ""
        self.worker = None
        self.wordlist = ""

        central = QWidget()
        self.setCentralWidget(central)
        lay = QVBoxLayout(central)

        self.drop = DropLabel()
        self.drop.file_dropped.connect(self.set_file)
        lay.addWidget(self.drop)

        mode_row = QHBoxLayout()
        mode_row.addWidget(QLabel("Mode:"))
        self.cmb_mode = QComboBox()
        self.cmb_mode.addItem("Auto (GPU first, then CPU fallback)", "auto")
        self.cmb_mode.addItem("GPU Crack (all GPUs via hashcat)", "gpu")
        self.cmb_mode.addItem("CPU Crack (john, for weak/no GPU)", "cpu")
        self.cmb_mode.addItem("Instant Unlock (fast, PDF restrictions only)", "instant")
        mode_row.addWidget(self.cmb_mode, 1)
        lay.addLayout(mode_row)

        wl_row = QHBoxLayout()
        self.lbl_wl = QLabel("Wordlist: built-in")
        self.lbl_wl.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        self.btn_wl = QPushButton("Wordlist...")
        self.btn_wl.clicked.connect(self.pick_wordlist)
        wl_row.addWidget(self.lbl_wl, 1)
        wl_row.addWidget(self.btn_wl)
        lay.addLayout(wl_row)

        row = QHBoxLayout()
        self.btn_pick = QPushButton("Choose File...")
        self.btn_pick.clicked.connect(self.pick_file)
        self.btn_start = QPushButton("Crack with GPU")
        self.btn_start.clicked.connect(self.start)
        self.btn_stop = QPushButton("Stop")
        self.btn_stop.clicked.connect(self.stop)
        self.btn_stop.setEnabled(False)
        self.btn_log = QPushButton("Log ▾")
        self.btn_log.setCheckable(True)
        self.btn_log.setChecked(True)
        self.btn_log.setToolTip("Collapse/expand the log panel")
        self.btn_log.clicked.connect(self.toggle_log)
        row.addWidget(self.btn_pick)
        row.addWidget(self.btn_start)
        row.addWidget(self.btn_stop)
        row.addWidget(self.btn_log)
        lay.addLayout(row)

        self.lbl_file = QLabel("File: none")
        self.lbl_file.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        lay.addWidget(self.lbl_file)

        self.lbl_gpu = QLabel("GPU: detecting...")
        lay.addWidget(self.lbl_gpu)

        self.lbl_status = QLabel("Ready.")
        f = QFont()
        f.setBold(True)
        f.setPointSize(11)
        self.lbl_status.setFont(f)
        lay.addWidget(self.lbl_status)

        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setPlaceholderText("Process output will appear here...")
        lay.addWidget(self.log, 1)

        res_row = QHBoxLayout()
        self.lbl_pass = QLabel("Password: -")
        self.lbl_pass.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        pf = QFont()
        pf.setPointSize(13)
        pf.setBold(True)
        self.lbl_pass.setFont(pf)
        self.btn_copy = QPushButton("Copy")
        self.btn_copy.clicked.connect(self.copy_pass)
        self.btn_copy.setEnabled(False)
        self.found_pass = ""
        res_row.addWidget(self.lbl_pass, 1)
        res_row.addWidget(self.btn_copy)
        lay.addLayout(res_row)

        gpus = gpu_names()
        if gpus:
            short = " | ".join(gpus)[:220]
            self.lbl_gpu.setText(f"GPU: all devices used - {short}")
        else:
            self.lbl_gpu.setText("GPU: all devices found by hashcat will be used")

        if start_file and os.path.isfile(start_file):
            self.set_file(start_file)

    def pick_wordlist(self):
        p, _ = QFileDialog.getOpenFileName(self, "Select wordlist", "", "Text (*.txt *.lst);;All (*)")
        if p:
            self.wordlist = p
            self.lbl_wl.setText(f"Wordlist: {p}")

    def pick_file(self):
        p, _ = QFileDialog.getOpenFileName(self, "Select file", "", FILE_FILTER)
        if p:
            self.set_file(p)

    def set_file(self, path):
        self.target_path = path
        kind = file_kind(path)
        self.lbl_file.setText(f"File: {path}  [{kind}]")
        self.drop.setText(f"Selected [{kind}]:\n{os.path.basename(path)}\n\nYou can drop another file")
        self.log.appendPlainText(f"Selected [{kind}]: {path}")
        self.start()

    def start(self):
        if not self.target_path:
            QMessageBox.warning(self, APP_NAME, "Select a file first.")
            return
        if self.worker and self.worker.isRunning():
            return
        self.log.clear()
        self.found_pass = ""
        self.btn_copy.setEnabled(False)
        self.lbl_pass.setText("Password: -")
        self.worker = CrackWorker(self.target_path, self.cmb_mode.currentData(), self.wordlist)
        self.worker.line.connect(self.log.appendPlainText)
        self.worker.step.connect(lambda t: self.lbl_status.setText(f"Working: {t}"))
        self.worker.finished_ok.connect(self.on_ok)
        self.worker.finished_fail.connect(self.on_fail)
        self.worker.finished.connect(self.on_done)
        self.btn_start.setEnabled(False)
        self.btn_stop.setEnabled(True)
        self.lbl_status.setText("Started...")
        self.worker.start()

    def stop(self):
        if self.worker and self.worker.isRunning():
            self.worker.stop()
            self.lbl_status.setText("Stopping...")

    def toggle_log(self):
        show = self.btn_log.isChecked()
        self.log.setVisible(show)
        self.btn_log.setText("Log ▾" if show else "Log ▸")
        if not show:
            self.resize(self.width(), 340)
        else:
            self.resize(self.width(), max(self.height(), 560))

    def on_done(self):
        self.btn_start.setEnabled(True)
        self.btn_stop.setEnabled(False)

    def on_ok(self, password, step):
        if password.startswith("UNLOCKED_FILE::"):
            path = password.split("::", 1)[1]
            self.lbl_pass.setText(f"Unlocked copy: {path}")
            self.lbl_status.setText(f"Done! ({step})")
            self.found_pass = ""
            self.btn_copy.setEnabled(False)
            self.log.appendPlainText(f"\nUnlocked copy saved: {path}")
            QMessageBox.information(self, APP_NAME,
                                    f"No cracking needed.\nUnlocked copy saved:\n{path}")
            return
        extra = ""
        if "||" in password:
            password, extra = password.split("||", 1)
        self.found_pass = password
        shown = "(blank password)" if password == "" else password
        self.lbl_pass.setText(f"Password: {shown}{extra}")
        self.lbl_status.setText(f"Found! ({step})")
        self.btn_copy.setEnabled(True)
        QMessageBox.information(self, APP_NAME, f"Password found: {shown}{extra}")
        QApplication.clipboard().setText(password)

    def on_fail(self, reason):
        self.lbl_status.setText("Done.")
        self.log.appendPlainText("\n" + reason)

    def copy_pass(self):
        if self.found_pass is not None:
            QApplication.clipboard().setText(self.found_pass)


def main():
    app = QApplication(sys.argv)
    start = sys.argv[1] if len(sys.argv) > 1 else ""
    w = MainWindow(start)
    w.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
