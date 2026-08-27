# Python version

A cross-platform **Python + Qt** port of the Hexapod IK & Workspace Calculator. It
reproduces the original MATLAB tool's geometry, math, file formats, and workflow, and is what the
**Windows `.exe`** is built from. Use this version to run on **macOS/Linux**, to build your own
binary, or to read and modify the source.

For the full description of what the tool does (geometry, IK, workspace analysis, screenshots), see
the [main README](../README.md).

**Beyond the MATLAB feature set, this version adds:** an always-on **docked console** (drag the
window's bottom edge to extend it), **light / dark / system** colour themes, a startup **splash
screen**, a crisp **app icon** on every window, a **transparent** embedded 3D preview, **Enter =
Solve IK**, MATLAB-style greying of disabled fields, **artifact-free** structured-grid workspace
surfaces with an isometric default view, and fully **non-blocking** workspace/PNG rendering (with an
**Abort** button — no frozen windows).

---

## Requirements

- **Python 3.11 or 3.12** recommended (3.13/3.14 may work but are less battle-tested for the
  PySide6 + VTK + PyInstaller stack).
- Dependencies are installed from `requirements.txt` (PySide6, PyVista, pyvistaqt, matplotlib,
  NumPy, SciPy; PyInstaller for building).

## Run from source

```bash
cd python
python -m venv .venv
# Windows:        .venv\Scripts\activate
# macOS / Linux:  source .venv/bin/activate

pip install -r requirements.txt
python run.py
```

On Windows, if `python`/`pip` aren't on your PATH, the `py` launcher works too: `py -m venv .venv`,
`py -m pip install -r requirements.txt`, `py run.py`.

The app starts from the `formdata.txt` in this folder. If that file is missing or invalid, it falls
back to built-in defaults and writes a fresh `formdata.txt` (reported on the splash and in the
console) — no blocking prompts.

---

## Build a standalone binary

PyInstaller is **not** a cross-compiler — build on the OS you want to target.

### Windows → single `.exe`
```bat
build_windows.bat
```
…or the equivalent single command:
```bat
py -m PyInstaller --clean --noconfirm hexapod.spec
```
Result: `dist\HexapodCalculator.exe`. A default `formdata.txt` is bundled inside; drop your own
next to the `.exe` to start from your settings.

**Build options (environment variables, no file edits needed):**

| Variable | Effect |
|---|---|
| `set HEXAPOD_ONEFILE=0` | Build a one-**folder** app (`dist\HexapodCalculator\`) that **starts much faster** and is friendlier to antivirus. The tradeoff is a folder instead of a single file. |
| `set HEXAPOD_CONSOLE=1` | Attach a console window so you can see startup output/errors (debugging). |
| `set HEXAPOD_SPLASH=0` | Disable the native bootloader splash. |

> **One-file vs one-folder:** a one-file `.exe` unpacks its whole bundle to a temp folder on *every*
> launch, which costs a few seconds of startup. A one-folder build skips that and starts almost
> instantly. Pick one-folder if startup speed matters more than shipping a single file.

### macOS → `.app`
```bash
./build_macos.sh
```
Result: `dist/HexapodCalculator.app`. First launch: right-click → **Open** to clear Gatekeeper
(the app isn't notarized).

### Linux → executable
```bash
./build_linux.sh
```
Result: `dist/HexapodCalculator`. Needs system OpenGL libraries, e.g.
`sudo apt install libgl1 libegl1 libxkbcommon0 libdbus-1-3`.

> macOS and Linux builds are provided as-is and are **currently untested** — they should work but
> may need small tweaks. Reports/PRs welcome.

---

## Performance

Workspace sweeps are vectorised and **chunked** (bounded memory) and run on a background thread so
the UI stays responsive and can be **Aborted** mid-run. The rendered surface is a clean
**structured-grid mesh** (no alpha-shape artifacts at any resolution). Approximate run times (a
typical laptop is a few times slower):

| Resolution | Search points | Time |
|---|---|---|
| Low    | ~0.16 M | ~2 sec  (quick preview) |
| Medium | ~1.0 M  | ~10 sec |
| High   | ~13 M   | ~2–4 min  (finest) |

The full point cloud sets the reported workspace limits; the rendered mesh is strided down for fast
drawing. The NumPy kernel is already faster than the compiled MATLAB MEX, so **you do not need to
compile any C code**. An optional C-DLL path exists — see [`native/README.md`](native/README.md).

---

## File formats (interchangeable with MATLAB)

- **`formdata.txt`** — identical to the MATLAB format: 76 `tag = value` lines at 3 decimals
  (`base1x, base1y, base1z, … plat6z`, the limits, legs, poses, `jointmin, jointmax, zpdLegLength,
  actuatorLead`; the order is `config.TAGS`), then `calculator_name = '...'`. When more than one
  origin is defined (or Origin 1 has been renamed) the origin lines follow, which both programs read
  and write; the number of origins is simply the number of `origin_k` lines:

  ```
  rpy_axes = 'ZXY'
  origin_1 = 'Origin 1', 0.000, 0.000, 0.000, 0.000, 0.000, 0.000
  origin_2 = 'Pupil plane', 12.000, -3.500, 250.000, 0.000, 0.000, 30.000
  origin_active = 2
  ```

  Each origin line holds the frame's X, Y, Z offset [mm] and roll, pitch, yaw orientation [°]
  relative to Origin 1; the `rpy_axes` line (only written when not the default XYZ) says which axis
  roll, pitch and yaw rotate about. Origin lines with only the three offsets are still read
  (orientation zero) and rewritten. An optional `adj_decimals` line and one `adj_k` line per origin
  (`adj_1 = 'X--R--', 15.0, 1.0, 1.0, 1.0, 1.0, 1.0`: a six-letter mask X Y Z R P W of the ticked axes
  and the six turns) hold the Incremental Adj. Table set-up, written only when it is not the default.

  The numeric values are always stored exactly as displayed, i.e. in the frame of the active origin,
  so a file reloads to precisely what was on screen. When reading, any decimal number is accepted
  on a value line (a hand-edited `1.0011109` or `5`) and rounded to three decimals. Older files are
  read and converted forward as well: the 69-tag layout with a single `baseZ` / `platZheight` plane
  height (copied to every joint; `benchZheight`, `benchThickness` and `platToBenchBottomZ` are
  dropped) and files with an `origin_count` line. Whenever a file differs from the canonical
  layout it is rewritten at start-up, with a console message saying why.
- **Workspace datasets** — saved as compressed **`.npz`**. The Recall/PNG dialogs can also load the
  original MATLAB **`.mat`** files (v7 via SciPy; v7.3/HDF5 needs the optional `h5py`).

---

## Project structure

```
python/
  run.py                 entry point (python run.py)
  requirements.txt
  hexapod.spec           PyInstaller spec (VTK hidden imports, data bundling, splash)
  build_windows.bat      one-click Windows build
  build_macos.sh / build_linux.sh
  formdata.txt           default settings / working file
  hexapod/
    config.py            tags, defaults, colours, MATLAB->Qt coordinate map
    kinematics.py        IK solvers + vectorised sweep engine + optional C-DLL loader
    settings_io.py       strict formdata.txt read/validate/write
    workspace.py         reachable/orientation sweeps, surface build, NEW/RECALL persistence
    console_stream.py    stdout/stderr mirror -> the docked console
    platform_view.py     embedded 3D platform plot + animation (matplotlib)
    workspace_view.py    PyVista surface render + PNG rotation export
    dialogs.py           adjust / workspace-progress / PNG-export / origins / change-coords / quit dialogs
    widgets.py           value / integer / name boxes: standard clipboard, instant rounding to 3 decimals
    adj_table.py         incremental adjustment table: maths, turn multipliers, text / Excel / PNG export
    splash.py            startup splash screen (logo + status + cancel)
    main_window.py       full GUI assembly + all callbacks + worker threads
    _startup_log.py      writes a small startup log for diagnosing frozen-build issues
  native/                optional fast C kernel (not required) + build scripts
  assets/                app icon (.ico/.icns/.png) + splash images
```

---

## Troubleshooting

- **`ModuleNotFoundError: vtkmodules...` in the built app** — build with `hexapod.spec` (not a bare
  `pyinstaller run.py`); the spec lists the VTK hidden imports.
- **One-file exe is slow to start** — it unpacks to a temp folder on launch; use the one-folder
  build (`set HEXAPOD_ONEFILE=0`) for near-instant startup. Expected behaviour, not a bug.
- **Antivirus flags a one-file exe** — common for PyInstaller one-file builds; prefer the one-folder
  build and/or code-sign the executable.
- **A build ever hangs or crashes on launch** — a startup log is written to
  `%LOCALAPPDATA%\HexapodCalculator\startup.log` (Windows) / `~/.HexapodCalculator/startup.log`;
  the last line tells you how far it got.
- **Use a plain venv, not conda** — conda's VTK can confuse PyInstaller.
- **"Multiple Qt bindings" build error** — build inside the `.venv` (which has only PySide6). The
  spec already excludes PyQt5/PyQt6/PySide2 to guard against a polluted global interpreter.

---

## Credits

Original MATLAB tool by **Joe Brown** (CSU Sacramento, 2006), adapted and extended by
**Adam B. Johnson** (University of Victoria, 2022–2025). This port preserves their algorithms and
layout while modernising the implementation and packaging.
