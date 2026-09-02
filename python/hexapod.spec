# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec for the Hexapod Calculator (cross-platform).

Build:
    Windows:  py -m PyInstaller --clean --noconfirm hexapod.spec   ->  dist/HexapodCalculator.exe
    macOS:    python3 -m PyInstaller --clean --noconfirm hexapod.spec -> dist/HexapodCalculator.app
    Linux:    python3 -m PyInstaller --clean --noconfirm hexapod.spec -> dist/HexapodCalculator

Set onefile=False for a faster-starting one-folder build (recommended for
distribution / friendlier to antivirus). The macOS .app is produced either way.

Environment-variable overrides (no need to edit this file):
    set HEXAPOD_ONEFILE=0   ->  one-folder build (faster start; a folder, not 1 file)
    set HEXAPOD_CONSOLE=1   ->  attach a console window so you can SEE startup output
                                / errors (debugging a hang or crash).
"""
import os
import sys
from PyInstaller.utils.hooks import collect_submodules, collect_data_files

# Defaults; overridable via env vars so a debug build needs no file edits.
onefile = os.environ.get("HEXAPOD_ONEFILE", "1") != "0"
show_console = os.environ.get("HEXAPOD_CONSOLE", "0") == "1"

block_cipher = None
IS_WIN = sys.platform.startswith("win")
IS_MAC = sys.platform == "darwin"

# Bootloader splash: shows the splash image the instant the exe is clicked -
# BEFORE Python starts - during the one-file unpack, then displays the loading
# status.  This is the "splash first, then status" behaviour.  It renders with
# Tcl/Tk, so tkinter must NOT be excluded below.  On by default; disable with
# set HEXAPOD_SPLASH=0.
enable_splash = (os.environ.get("HEXAPOD_SPLASH", "1") != "0") and not IS_MAC

# --- VTK needs its submodules collected explicitly ---
hidden = []
hidden += collect_submodules("vtkmodules")
hidden += [
    "vtkmodules.all",
    "vtkmodules.util.numpy_support",
    "vtkmodules.numpy_interface",
    "vtkmodules.numpy_interface.dataset_adapter",
    "vtkmodules.qt",
    "vtkmodules.qt.QVTKRenderWindowInteractor",
]
hidden += collect_submodules("pyvista")
hidden += collect_submodules("pyvistaqt")

# --- data files (bundled into the app on every platform) ---
datas = []
datas += collect_data_files("pyvista")
# app icon (.ico/.png) + splash logo so windows/dialogs can load them at runtime
for ic in ("assets/icon.ico", "assets/icon.png", "assets/splash.png"):
    if os.path.exists(ic):
        datas += [(ic, "assets")]
# ship a default settings file next to the app if present
if os.path.exists("formdata.txt"):
    datas += [("formdata.txt", ".")]

# --- optional compiled C kernel (only if you built it; safe to omit) ---
# matches the right shared-library extension for the build OS.
binaries = []
_libnames = ["stew_inverse_ws.dll"] if IS_WIN else \
            (["stew_inverse_ws.dylib"] if IS_MAC else ["stew_inverse_ws.so"])
for base in _libnames:
    for cand in (os.path.join("native", base), base):
        if os.path.exists(cand):
            binaries += [(cand, ".")]
            break

# --- platform-appropriate executable icon ---
if IS_MAC:
    icon = "assets/icon.icns" if os.path.exists("assets/icon.icns") else None
elif IS_WIN:
    icon = "assets/icon.ico" if os.path.exists("assets/icon.ico") else None
else:
    icon = None   # Linux: no embedded binary icon; the window icon is set at runtime via Qt

a = Analysis(
    ["run.py"],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hidden,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
              # tkinter is intentionally NOT excluded: the bootloader splash
              # (above) is drawn with Tcl/Tk, so the runtime must be bundled.
              # Only PySide6 is used, so exclude the other Qt bindings to stop
              # PyInstaller aborting with "attempt to collect multiple Qt
              # bindings" if the build interpreter also has PyQt installed.
              "PyQt5", "PyQt6", "PySide2"],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

# Native splash: displayed by the bootloader during startup/extraction.  Rendered
# with Tcl/Tk; if that isn't available in the build interpreter, fall back to no
# native splash rather than aborting the whole build (the Qt splash still shows).
splash = None
if enable_splash and os.path.exists("assets/splash_native.png"):
    try:
        splash = Splash(
            "assets/splash_native.png",
            binaries=a.binaries,
            datas=a.datas,
            text_pos=(18, 460),             # bottom-left; matched to the Qt splash text height
            text_size=9,
            text_color="#3a3a3a",
            text_default="Starting up...",
            always_on_top=True,
        )
        print("PyInstaller splash: enabled (assets/splash_native.png)")
    except Exception as _e:
        print(f"PyInstaller splash: DISABLED - Tcl/Tk unavailable ({_e}). "
              f"Build continues; the Qt splash will be used instead.")
        splash = None

if onefile:
    _toc = [a.scripts]
    if splash is not None:
        _toc += [splash, splash.binaries]
    _toc += [a.binaries, a.zipfiles, a.datas, []]
    exe = EXE(
        pyz, *_toc,
        name="HexapodCalculator",
        debug=False, bootloader_ignore_signals=False, strip=False,
        upx=False, upx_exclude=[], runtime_tmpdir=None,
        console=show_console, icon=icon,
    )
    target = exe
else:
    _toc = [a.scripts]
    if splash is not None:
        _toc += [splash]                # only the splash TOC goes in the EXE
    _toc += [[]]
    exe = EXE(
        pyz, *_toc,
        exclude_binaries=True,          # one-folder: COLLECT gathers the binaries,
        name="HexapodCalculator",       # so the EXE itself must not embed them
        debug=False, bootloader_ignore_signals=False, strip=False,
        upx=False, console=show_console, icon=icon,
    )
    _coll = [exe, a.binaries, a.zipfiles, a.datas]
    if splash is not None:
        _coll += [splash.binaries]      # splash binaries collected alongside
    coll = COLLECT(
        *_coll,
        strip=False, upx=False, upx_exclude=[], name="HexapodCalculator",
    )
    target = coll

# --- macOS: wrap into a .app bundle so it launches as a normal GUI app ---
if IS_MAC:
    app = BUNDLE(
        target,
        name="HexapodCalculator.app",
        icon=icon,
        bundle_identifier="ca.uvic.hexapod-calculator",
        info_plist={
            "NSHighResolutionCapable": True,
            "NSPrincipalClass": "NSApplication",
            "CFBundleName": "Hexapod Calculator",
            "CFBundleDisplayName": "Hexapod Calculator",
        },
    )
