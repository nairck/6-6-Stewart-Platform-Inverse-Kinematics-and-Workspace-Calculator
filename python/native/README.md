# Optional: compiled C kernel for maximum speed

**You almost certainly do not need this.** The application already uses a fully
vectorised NumPy kernel that is **25-50x faster** than the original MATLAB+MEX
build and produces numerically identical results. This folder only matters if
you want to squeeze out extra speed by dropping in a compiled C library.

If a compiled kernel named `stew_inverse_ws.dll` (Windows), `libstew_inverse_ws.so`
(Linux), or `libstew_inverse_ws.dylib` (macOS) is found next to the executable
or in this folder, the app loads it automatically; otherwise it silently uses
the NumPy path.

---

## Why the kernel in the original project will not work directly

The `codegen/mex/` folder in the original MATLAB project is a **MEX** build. Its
entry point looks like:

```c
void stew_inverse_ws(const emlrtStack *sp, const real_T xsi[6], ...);
```

That `emlrtStack *sp` argument means it depends on the MATLAB runtime (`emlrt`)
and **cannot** be loaded as a standalone library from Python. You must
regenerate a standalone build.

## Regenerating a standalone library with MATLAB Coder

In MATLAB, from the project's `Hexapod Calculator ...` folder:

```matlab
cfg = coder.config('dll');          % or 'lib' for a static library
cfg.GenCodeOnly = false;
args = {zeros(1,6), zeros(1,6), zeros(1,6), zeros(1,6), zeros(1,6), zeros(1,6), ...
        0, 0, 0, 0, 0, 0};    % xsi ysi zsi xmi ymi zmi roll pitch yaw px py pz
codegen stew_inverse_ws -config cfg -args args
```

This produces a standalone `stew_inverse_ws.c/.h` with the clean signature:

```c
void stew_inverse_ws(const double xsi[6], const double ysi[6], const double zsi[6],
                     const double xmi[6], const double ymi[6], const double zmi[6],
                     double roll, double pitch, double yaw,
                     double px, double py, double pz,
                     double Legs[6]);
```

Copy the generated `*.c` / `*.h` files into this `native/` folder, then build
with one of the scripts below.

## Building the DLL/so/dylib

- **Windows (MSVC, "x64 Native Tools Command Prompt"):** run `build_dll.bat`
- **Linux/macOS:** run `./build_dll.sh`

The app's ctypes wrapper expects the exact standalone signature above. See
`hexapod/kinematics.py` (`_CKernel`) for details.
