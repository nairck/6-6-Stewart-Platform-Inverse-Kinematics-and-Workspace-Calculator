# Python version

A cross-platform **Python + Qt** port of the Hexapod IK & Workspace Calculator, and the source the
**Windows executable** is built from. It reproduces the MATLAB tool's geometry, maths, file formats
and workflow. Use it to run on macOS or Linux, to build your own binary, or to read the source.

For what the tool does (geometry, inverse kinematics, origins, the incremental adjustment table,
workspace analysis, screenshots), see the [main README](../README.md).

Beyond the MATLAB feature set this version adds a docked console, light / dark / system themes, a
startup splash screen, a transparent embedded 3D preview, Enter to solve, artifact-free
structured-grid workspace surfaces, and non-blocking workspace and PNG rendering with an Abort
button.

Version 1.2.

---

## Requirements

- **Python 3.11 or 3.12** recommended (3.13 and 3.14 usually work, but are less tested against the
  PySide6 + VTK + PyInstaller stack). Everything else installs from `requirements.txt`: PySide6,
  PyVista, pyvistaqt, matplotlib, NumPy, SciPy, and PyInstaller for building.

**Windows.** Nothing else is needed. Install Python from python.org (tick "Add python.exe to PATH"),
then follow *Run from source* below, or just download the `.exe` from the
[Releases page](../../releases).

**Linux.** Qt, VTK and matplotlib need system libraries that no Python package provides, and
PyInstaller needs `objdump`. A minimal Ubuntu or Debian install has none of them. One command
installs the lot:

```bash
sudo apt update
sudo apt install -y python3-venv python3-pip python3-dev python3-tk   binutils patchelf file wget   libxcb-cursor0 libxcb-xinerama0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1   libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-shm0 libxcb-sync1   libxcb-xfixes0 libxcb-xkb1 libx11-xcb1 libxkbcommon-x11-0 libxkbcommon0   libgl1 libegl1 libglu1-mesa libdbus-1-3 libfontconfig1 libfreetype6   libxrender1 libxi6 libsm6 libice6
```

Three of these fail with messages that do not name the package: without `libxcb-cursor0` the program
exits with "Could not load the Qt platform plugin xcb", without `binutils` PyInstaller stops with
"On Linux, objdump is required", and without `python3-tk` it stops on a missing `_tkinter`. On
Fedora use `dnf` with `python3-devel`, `python3-tkinter`, the `xcb-util-*` packages, `mesa-libGL`,
`mesa-libEGL`, `libxkbcommon-x11`, `fontconfig`, `dbus-libs` and `binutils`; on Arch use `pacman`
with `tk`, `xcb-util-*`, `libglvnd`, `libxkbcommon-x11`, `fontconfig` and `binutils`.

Users of the released Linux build **need none of this**: the single file carries everything.

## Run from source

```bash
cd python
python -m venv .venv
# Windows:        .venv\Scripts\activate
# macOS / Linux:  source .venv/bin/activate

pip install -r requirements.txt
python run.py
```

On Windows the `py` launcher works too: `py -m venv .venv`, `py -m pip install -r requirements.txt`,
`py run.py`.

## Build a standalone program

Always build with the spec file, which lists the VTK hidden imports and bundles the assets.

**Windows** produces `dist\HexapodCalculator.exe`:

```bat
build_windows.bat
```

**Linux** produces `dist/HexapodCalculator`, a single double-clickable file that needs nothing
installed on the machine that runs it, not even Python:

```bash
cd python
chmod +x build_linux.sh     # a zip does not keep the executable permission
./build_linux.sh
```

The build takes a few minutes and asks for your password once, to install what the machine is
missing. Run the result with `./dist/HexapodCalculator`, or double-click it.

It is an AppImage, without the extension, so it looks and behaves like an ordinary program. The
script installs whatever the build machine is missing, compiles with PyInstaller, adds the X/xcb
libraries Qt loads at run time (PyInstaller cannot detect them, and their absence is the usual cause
of "platform plugin xcb" on someone else's machine), and packs the result with its icon.

A Linux executable cannot carry a file-manager icon the way a Windows `.exe` does, so the program
registers a MIME type for itself the first time it runs, with the icon attached to it. Nothing is
added to the desktop or the applications menu, and `./HexapodCalculator --uninstall-icon` removes
the registration.

**macOS** produces `dist/HexapodCalculator.app`:

```bash
chmod +x build_macos.sh
./build_macos.sh
```

### Building a Linux release for older distros

glibc is forward compatible only, so a binary built on Ubuntu 24.04 will not start on 22.04.
Build on the oldest system you intend to support. A container does that without installing anything
but Docker:

```bash
cd python
docker run --rm -v "$PWD/..":/src -w /src/python ubuntu:22.04 bash -c \
  'apt update && apt install -y sudo && ./build_linux.sh'
```

The file it writes runs on Ubuntu 22.04 and everything newer.

Set `HEXAPOD_ONEFILE=0` before `build_windows.bat` for a one-folder Windows build, which starts
almost instantly; the default one-file build unpacks to a temporary folder on every launch.

## Performance

Workspace sweeps are vectorised, chunked to bound memory, and run on a background thread, so the
window stays responsive and a sweep can be aborted. Approximate times on a desktop machine:

| Resolution | Search points | Time |
|---|---|---|
| Low    | ~0.16 M | ~2 s, quick preview |
| Medium | ~1.0 M  | ~10 s |
| High   | ~13 M   | ~2 to 4 min, finest |

The full point cloud sets the reported limits; the drawn mesh is strided down for speed. The NumPy
kernel is faster than the compiled MATLAB MEX, so no C code needs building. An optional C library
path exists, described in [`native/README.md`](native/README.md).

## File formats

Both programs read and write the same files.

**`formdata.txt`** holds 76 `tag = value` lines at three decimals (`base1x` through `plat6z`, the
search limits, legs, poses, `jointmin`, `jointmax`, `zpdLegLength`, `actuatorLead`; the order is
`config.TAGS`), then `calculator_name`. Optional blocks follow when they carry information:

```
rpy_axes = 'ZXY'
origin_1 = 'Origin 1', 0.000, 0.000, 0.000, 0.000, 0.000, 0.000
origin_2 = 'Pupil plane', 12.000, -3.500, 250.000, 0.000, 0.000, 30.000
origin_active = 2
adj_decimals = 3
adj_1 = 'X--R--', 15.0, 1.0, 1.0, 1.0, 1.0, 1.0, 'focus in', '', '', '', '', ''
```

- Each origin line carries the frame's X, Y, Z offset [mm] and its roll, pitch, yaw orientation [°]
  relative to Origin 1; `rpy_axes` says which axis roll, pitch and yaw rotate about.
- Each `adj_k` line carries the Incremental Adj. Table set-up for that origin: a six-letter mask of
  the ticked axes (X Y Z R P W), the six turn multipliers, and the six row labels when any were
  typed.

Values are stored exactly as displayed, in the active origin's frame, so a file reloads to what was
on screen. Any decimal number is accepted when reading and rounded to three decimals. Older files
are read and converted: the 69-tag layout with single `baseZ` / `platZheight` plane heights (copied
to every joint, the bench values dropped) and files with an `origin_count` line. A file that differs
from the canonical layout is rewritten at start-up, with a console message saying why.

**Workspace datasets** are saved as compressed `.npz`. The recall and PNG dialogs also read the
MATLAB `.mat` files (v7 through SciPy; v7.3 needs the optional `h5py`).

## Project structure

```
python/
  run.py                 entry point
  requirements.txt
  hexapod.spec           PyInstaller spec
  build_windows.bat, build_macos.sh, build_linux.sh
  formdata.txt           default settings / working file
  hexapod/
    config.py            tags, defaults, colours, geometry constants
    kinematics.py        IK solvers, sweep engine, frame and axis maths
    settings_io.py       formdata.txt read, validate, write
    workspace.py         reachable and orientation sweeps, surfaces, persistence
    platform_view.py     embedded 3D sketch, animation, off-screen render for exports
    workspace_view.py    PyVista surface render and PNG rotation export
    adj_table.py         incremental adjustment table: maths and text / PNG / Excel export
    dialogs.py           origins, change coords, adjustment table, workspace and quit dialogs
    widgets.py           value, integer and name boxes with clipboard and live rounding
    savedir.py           the save folder remembered across every file dialog
    console_stream.py    stdout and stderr mirrored to the docked console
    splash.py            startup splash screen
    main_window.py       GUI assembly, callbacks, worker threads
  native/                optional C kernel, not required
  assets/                icons and splash images
```

## Troubleshooting

- **`ModuleNotFoundError: vtkmodules...` in a built app** — build with `hexapod.spec`, not a bare
  `pyinstaller run.py`.
- **The one-file executable is slow to start** — it unpacks on launch; use the one-folder build.
- **Antivirus flags a one-file executable** — common for PyInstaller; prefer the one-folder build,
  or code-sign it.
- **A build hangs or crashes on launch** — a startup log is written to
  `%LOCALAPPDATA%\HexapodCalculator\startup.log` on Windows, `~/.HexapodCalculator/startup.log`
  elsewhere; the last line says how far it got.
- **Build with a plain venv, not conda** — conda's VTK confuses PyInstaller.
- **"Multiple Qt bindings" at build time** — build inside `.venv`, which has only PySide6.
- **Linux: "Could not load the Qt platform plugin xcb"** — `libxcb-cursor0` is missing; see
  Requirements.
- **Linux: "On Linux, objdump is required"** — install `binutils`.
- **Linux: the build stops on `_tkinter`** — install `python3-tk`; matplotlib's splash needs it.
- **Linux: the icon does not appear on the file** — press F5 in the folder. Only the very first
  registration on a machine may need the file manager restarted.

## Credits

Original MATLAB tool by **Joe Brown** (CSU Sacramento, 2006), adapted and extended by
**Adam B. Johnson** (University of Victoria, 2022 to 2026). This port keeps their algorithms and
layout while modernising the implementation and packaging.
