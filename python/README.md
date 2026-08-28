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
  PySide6 + VTK + PyInstaller stack).
- Everything else installs from `requirements.txt`: PySide6, PyVista, pyvistaqt, matplotlib, NumPy,
  SciPy, and PyInstaller for building.

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

## Build a standalone binary

Always build with the spec file, which lists the VTK hidden imports and bundles the assets.

```bash
# Windows           one-click, produces dist\HexapodCalculator.exe
build_windows.bat

# macOS / Linux
./build_macos.sh
./build_linux.sh

# or directly, on any platform
pyinstaller hexapod.spec
```

Set `HEXAPOD_ONEFILE=0` before building for a one-folder build, which starts almost instantly; the
default one-file build unpacks to a temporary folder on every launch.

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

## Credits

Original MATLAB tool by **Joe Brown** (CSU Sacramento, 2006), adapted and extended by
**Adam B. Johnson** (University of Victoria, 2022 to 2026). This port keeps their algorithms and
layout while modernising the implementation and packaging.
