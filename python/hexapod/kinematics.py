"""Inverse kinematics for a hexapod (6-6 Gough-Stewart platform).

Direct port of stew_inverse.m and stew_inverse_ws.m.  The NumPy kernels here
were validated to reproduce the original MATLAB leg lengths to < 5e-4 mm (i.e.
identical at the 3-decimal precision the tool uses), and the vectorised sweep
kernel is what makes the workspace solver 25-50x faster than the MATLAB+MEX
version while remaining numerically identical.

An optional compiled C kernel (stew_inverse_ws DLL/so/dylib) can be dropped in
for users who regenerate standalone code with MATLAB Coder; it is detected and
used automatically, otherwise the (already very fast) NumPy path is used.
"""
from __future__ import annotations
import os
import sys
import ctypes
import numpy as np


# ---------------------------------------------------------------------------
# Rotation matrix shared by both solvers (roll-pitch-yaw, degrees -> radians)
# ---------------------------------------------------------------------------
# Which coordinate axis each angle rotates about is a program setting, the
# "rpy axes" string: 'XYZ' (the default: roll about X, pitch about Y, yaw about
# Z), 'YZX' or 'ZXY'.  Only the cyclic assignments are allowed so the three
# rotation axes, taken in the order roll, pitch, yaw, always form a
# right-handed triad.  For an assignment with permutation matrix P (column i =
# the axis of angle i) the rotation is R = P R0 P^T with R0 the 'XYZ' matrix
# below, i.e. R = R_a0(roll) R_a1(pitch) R_a2(yaw): the same composition order
# about the assigned axes.
RPY_AXES_OPTIONS = ("XYZ", "YZX", "ZXY")


def rpy_perm(axes):
    """Permutation matrix P of an rpy-axes assignment: column i is the unit
    vector of the coordinate axis that angle i (roll, pitch, yaw) is about."""
    axes = str(axes).upper()
    if axes not in RPY_AXES_OPTIONS:
        raise ValueError(f"rpy axes must be one of {RPY_AXES_OPTIONS}, got {axes!r}")
    P = np.zeros((3, 3))
    for i, ch in enumerate(axes):
        P["XYZ".index(ch), i] = 1.0
    return P


def _rotation_xyz(roll, pitch, yaw):
    tx, ty, tz = np.radians(roll), np.radians(pitch), np.radians(yaw)
    cx, sx = np.cos(tx), np.sin(tx)
    cy, sy = np.cos(ty), np.sin(ty)
    cz, sz = np.cos(tz), np.sin(tz)
    return np.array([
        [cy * cz,                 -cy * sz,                  sy],
        [sx * sy * cz + cx * sz,  -sx * sy * sz + cx * cz,  -sx * cy],
        [-cx * sy * cz + sx * sz,  cx * sy * sz + sx * cz,   cx * cy],
    ])


def _rotation(roll, pitch, yaw, axes="XYZ"):
    R0 = _rotation_xyz(roll, pitch, yaw)
    if str(axes).upper() == "XYZ":
        return R0
    P = rpy_perm(axes)
    return P @ R0 @ P.T


def stew_inverse(xsi, ysi, zsi, xmi, ymi, zmi, roll, pitch, yaw, px, py, pz, axes="XYZ"):
    """Full inverse kinematics (port of stew_inverse.m).

    Every base joint (xsi, ysi, zsi) and platform joint (xmi, ymi, zmi) has its
    own X, Y, Z: no plane assumption for either set of joints.

    Returns a length-42 vector: [Legs(6), platcoords(18), animcoords(18)].
    platcoords and animcoords are identical (the original T and Ta matrices are
    identical), kept separate to preserve the original return layout.
    """
    a = np.column_stack([np.asarray(xsi, float), np.asarray(ysi, float),
                         np.asarray(zsi, float)])               # (6,3) base joints
    b = np.column_stack([np.asarray(xmi, float), np.asarray(ymi, float),
                         np.asarray(zmi, float)])               # (6,3) platform joints
    R = _rotation(roll, pitch, yaw, axes)
    t = np.array([px, py, pz], float)
    b_trans = (R @ b.T).T + t                                   # (6,3) transformed

    legs = np.sqrt(np.sum((a - b_trans) ** 2, axis=1))          # (6,)
    platcoords = b_trans.reshape(-1)                            # x1,y1,z1,x2,... (18,)
    animcoords = platcoords.copy()
    return np.concatenate([legs, platcoords, animcoords])


def stew_inverse_ws(xsi, ysi, zsi, xmi, ymi, zmi, roll, pitch, yaw, px, py, pz, axes="XYZ"):
    """Optimised kernel returning only the six leg lengths (port of stew_inverse_ws.m)."""
    a = np.column_stack([np.asarray(xsi, float), np.asarray(ysi, float), np.asarray(zsi, float)])
    b = np.column_stack([np.asarray(xmi, float), np.asarray(ymi, float), np.asarray(zmi, float)])
    R = _rotation(roll, pitch, yaw, axes)
    t = np.array([px, py, pz], float)
    b_trans = (R @ b.T).T + t
    return np.sqrt(np.sum((a - b_trans) ** 2, axis=1))


def legs_for_directions(a, b, R, center, n, radii):
    """Vectorised leg lengths for many probe points at once.

    This is the engine behind the fast workspace sweep.  For every direction
    `n[i]` and radius `radii[i]` it forms a probe point center + radii*n, applies
    the (fixed) rotation R to the platform joints b, and returns an (N, 6) array
    of leg lengths.  Pure array math -> no Python-level per-direction loop.

    a       : (6,3) base joints
    b       : (6,3) platform joints
    R       : (3,3) rotation for the chosen centre pose (constant during a sweep)
    center  : (3,) translation of the centre pose
    n       : (N,3) unit direction vectors
    radii   : (N,) radius per direction
    """
    points = center[None, :] + radii[:, None] * n          # (N,3)
    b_rot = (R @ b.T).T                                     # (6,3) rotated platform joints
    b_trans = b_rot[None, :, :] + points[:, None, :]        # (N,6,3)
    return np.sqrt(np.sum((a[None, :, :] - b_trans) ** 2, axis=2))   # (N,6)


# ---------------------------------------------------------------------------
# Origin / point-of-interest frame change
# ---------------------------------------------------------------------------
def shift_frame(e, roll, pitch, yaw, px, py, pz):
    """Re-express a pose when the coordinate origin is moved by -e.

    Every joint coordinate is translated by e (a_i' = a_i + e, b_i' = b_i + e),
    which places the new point of interest at the origin.  For the platform's
    physical position to be unchanged the leg vectors must be unchanged:

        a_i' - (R b_i' + p') = a_i - (R b_i + p)
        (a_i + e) - R b_i - R e - p' = a_i - R b_i - p
        p' = p + e - R e

    The rotation R (and therefore roll, pitch, yaw) is the same in both frames;
    only the translation changes.  Home (R = I, p = 0) maps to home in every
    frame, so "Go Home" means the same physical configuration for every origin.

    e : (3,) shift applied to the joint coordinates (old_offset - new_offset)
    Returns (px', py', pz').
    """
    e = np.asarray(e, float).reshape(3)
    R = _rotation(roll, pitch, yaw)
    p = np.array([px, py, pz], float)
    p_new = p + e - R @ e
    return float(p_new[0]), float(p_new[1]), float(p_new[2])


def origin_frame(origin, axes="XYZ"):
    """(R_o, d_o) of an origin / point of interest: its axes' rotation and its
    offset, both relative to Origin 1.  A point with Origin-1 coordinates p has
    coordinates R_o^T (p - d_o) in this frame."""
    R = _rotation(origin.get("roll", 0.0), origin.get("pitch", 0.0), origin.get("yaw", 0.0), axes)
    d = np.array([origin.get("dx", 0.0), origin.get("dy", 0.0), origin.get("dz", 0.0)], float)
    return R, d


def frame_transition(origin_from, origin_to, axes="XYZ"):
    """(M, e) taking coordinates expressed in origin_from's frame to
    origin_to's frame: q_to = M q_from + e, with M = R_to^T R_from and
    e = R_to^T (d_from - d_to).  Both origins are frames relative to Origin 1
    (see origin_frame); M is a proper rotation."""
    R_a, d_a = origin_frame(origin_from, axes)
    R_b, d_b = origin_frame(origin_to, axes)
    M = R_b.T @ R_a
    e = R_b.T @ (d_a - d_b)
    return M, e


def change_frame(M, e, roll, pitch, yaw, px, py, pz, axes="XYZ"):
    """Re-express a platform pose under the frame change q' = M q + e applied
    to every joint coordinate, so that every leg vector is the same physical
    vector (rotated by M) and every leg length is unchanged:

        a' - (R' b' + t') = M [a - (R b + t)]      with a' = M a + e, b' = M b + e
        =>  R' = M R M^T,   t' = M t + e - R' e

    (For M = I this is shift_frame: t' = t + e - R e.)  Returns (roll',
    pitch', yaw', px', py', pz') with the angles extracted for `axes`."""
    M = np.asarray(M, float)
    e = np.asarray(e, float).reshape(3)
    R2 = M @ _rotation(roll, pitch, yaw, axes) @ M.T
    t2 = M @ np.array([px, py, pz], float) + e - R2 @ e
    r2, p2, y2 = rpy_from_rotation(R2, axes)
    return r2, p2, y2, float(t2[0]), float(t2[1]), float(t2[2])


def rpy_from_rotation(R, axes="XYZ"):
    """Inverse of _rotation(): recover (roll, pitch, yaw) in degrees from a
    rotation matrix.  For the default 'XYZ' assignment R = Rx(roll) * Ry(pitch)
    * Rz(yaw); for another assignment R = P R0 P^T is first brought back to
    R0 = P^T R P.

    From the matrix layout:  R[0,2] = sin(pitch),  R[1,2] = -sin(roll)cos(pitch),
    R[2,2] = cos(roll)cos(pitch),  R[0,1] = -cos(pitch)sin(yaw),
    R[0,0] = cos(pitch)cos(yaw).  At |pitch| = 90 deg (never reached by this
    tool's few-degree poses) roll and yaw are not separable; roll is then set
    to 0 and the remaining rotation is assigned to yaw.
    """
    R = np.asarray(R, float)
    if str(axes).upper() != "XYZ":
        P = rpy_perm(axes)
        R = P.T @ R @ P
    sp = float(np.clip(R[0, 2], -1.0, 1.0))
    pitch = np.arcsin(sp)
    if abs(sp) < 1.0 - 1e-12:
        roll = np.arctan2(-R[1, 2], R[2, 2])
        yaw = np.arctan2(-R[0, 1], R[0, 0])
    else:                                   # gimbal lock
        roll = 0.0
        yaw = np.arctan2(R[1, 0], R[1, 1])
    return float(np.degrees(roll)), float(np.degrees(pitch)), float(np.degrees(yaw))


_AXIS_VECTORS = {
    "+X": (1, 0, 0), "-X": (-1, 0, 0),
    "+Y": (0, 1, 0), "-Y": (0, -1, 0),
    "+Z": (0, 0, 1), "-Z": (0, 0, -1),
}


def axis_vector(label):
    """Unit vector for a signed axis label such as '+X' or '-Z'."""
    return np.array(_AXIS_VECTORS[label], float)


def axis_label(vec):
    """Signed axis label for a unit axis vector (inverse of axis_vector)."""
    v = np.asarray(vec, float)
    k = int(np.argmax(np.abs(v)))
    return ("+" if v[k] > 0 else "-") + "XYZ"[k]


def axis_map_matrix(map_x, map_y, map_z):
    """Signed permutation matrix M for a relabelling of the coordinate axes.

    map_x is the signed new axis that the CURRENT X axis becomes (e.g. '+Y'),
    map_y / map_z likewise for the current Y and Z axes.  A vector with current
    coordinates v has new coordinates M @ v; the columns of M are the mapped
    axis vectors.  The combination must be right-handed (det M = +1, i.e.
    map_z == map_x x map_y), which the Change-Coords dialog enforces and this
    function checks.
    """
    cx, cy, cz = axis_vector(map_x), axis_vector(map_y), axis_vector(map_z)
    M = np.column_stack([cx, cy, cz])
    if abs(np.linalg.det(M) - 1.0) > 1e-9 or not np.allclose(np.cross(cx, cy), cz):
        raise ValueError("axis mapping is not a right-handed relabelling")
    return M


def remap_pose(M, roll, pitch, yaw, px, py, pz, axes="XYZ"):
    """Express a pose in relabelled axes.  Translation: p' = M p.  Rotation:
    the same physical rotation seen in the new axes is R' = M R M^T, from which
    the new roll / pitch / yaw are extracted (same rpy-axes assignment, now
    referring to the new axis names).  Returns (roll', pitch', yaw', px', py',
    pz')."""
    M = np.asarray(M, float)
    R2 = M @ _rotation(roll, pitch, yaw, axes) @ M.T
    r2, p2, y2 = rpy_from_rotation(R2, axes)
    t2 = M @ np.array([px, py, pz], float)
    return r2, p2, y2, float(t2[0]), float(t2[1]), float(t2[2])


def convert_rpy_axes(roll, pitch, yaw, old_axes, new_axes):
    """The same physical rotation described with another rpy-axes assignment:
    R = _rotation(angles, old_axes), then the angles are re-extracted for
    new_axes.  Returns (roll', pitch', yaw')."""
    return rpy_from_rotation(_rotation(roll, pitch, yaw, old_axes), new_axes)


def remap_rpy_limits(mins, maxs, old_axes, new_axes):
    """Each angle's [min, max] follows the coordinate axis it rotates about:
    under new_axes the angle about axis a receives the interval that the angle
    about a had under old_axes (cyclic assignments only, so no sign flip)."""
    old_axes, new_axes = str(old_axes).upper(), str(new_axes).upper()
    new_min = np.zeros(3); new_max = np.zeros(3)
    for j, ch in enumerate(new_axes):
        i = old_axes.index(ch)
        new_min[j], new_max[j] = mins[i], maxs[i]
    return new_min, new_max


def remap_limits(M, mins, maxs):
    """Remap per-axis [min, max] intervals (translation or rotation about the
    axes) under the relabelling M.  New axis j receives the interval of the
    current axis k it comes from (M[j, k] = s); a sign flip (s = -1) mirrors the
    interval: [min, max] -> [-max, -min].  mins/maxs are length-3 (X, Y, Z)."""
    M = np.asarray(M, float)
    mins = np.asarray(mins, float); maxs = np.asarray(maxs, float)
    new_min = np.zeros(3); new_max = np.zeros(3)
    for j in range(3):
        k = int(np.argmax(np.abs(M[j])))
        s = np.sign(M[j, k])
        if s > 0:
            new_min[j], new_max[j] = mins[k], maxs[k]
        else:
            new_min[j], new_max[j] = -maxs[k], -mins[k]
    return new_min, new_max


# ---------------------------------------------------------------------------
# Leg-output arithmetic (port of the maths in solve_inverse.m / overwrite_data.m)
# ---------------------------------------------------------------------------
def leg_revolutions_remainder(ang_delta_deg):
    """Split an angular delta (deg) into integer turns + signed remainder in
    (-360, 360), rounded to 0.1 deg, folding an exact +/-360 back into turns.
    Mirrors the leg_rev / leg_rem logic in solve_inverse.m."""
    ang = np.asarray(ang_delta_deg, float)
    rev = np.fix(ang / 360.0).astype(int)            # toward zero
    rem = np.round(ang - rev * 360.0, 1)
    roll_over = np.abs(rem) == 360.0
    rev = rev + np.where(roll_over, np.sign(ang).astype(int), 0)
    rem = np.where(roll_over, 0.0, rem)
    return rev, rem


# ---------------------------------------------------------------------------
# Optional compiled C kernel (auto-detected).  Falls back silently to NumPy.
# ---------------------------------------------------------------------------
class _CKernel:
    """ctypes wrapper around a standalone stew_inverse_ws shared library.

    The library MUST be the *standalone* (lib/dll) MATLAB Coder build with the
    signature:

        void stew_inverse_ws(const double xsi[6], const double ysi[6], const double zsi[6],
                             const double xmi[6], const double ymi[6], const double zmi[6],
                             double roll, double pitch, double yaw,
                             double px, double py, double pz, double Legs[6]);

    (per-joint Z for every base and platform joint; the previous baseZ /
    platformZ scalar signature is no longer accepted.)

    The MEX build shipped in the original project will NOT work (it needs the
    MATLAB runtime); regenerate with coder.config('dll').  See native/README.md.
    """

    def __init__(self, path):
        self.lib = ctypes.CDLL(path)
        c6 = ctypes.c_double * 6
        self.lib.stew_inverse_ws.restype = None
        self.lib.stew_inverse_ws.argtypes = [
            c6, c6, c6, c6, c6, c6,
            ctypes.c_double, ctypes.c_double, ctypes.c_double,
            ctypes.c_double, ctypes.c_double, ctypes.c_double, c6,
        ]
        for fn in ("stew_inverse_ws_initialize", "stew_inverse_ws_terminate"):
            if hasattr(self.lib, fn):
                getattr(self.lib, fn).restype = None
                getattr(self.lib, fn).argtypes = []
        if hasattr(self.lib, "stew_inverse_ws_initialize"):
            self.lib.stew_inverse_ws_initialize()

    def __call__(self, xsi, ysi, zsi, xmi, ymi, zmi, roll, pitch, yaw, px, py, pz, axes="XYZ"):
        if str(axes).upper() != "XYZ":
            raise NotImplementedError("the C kernel supports the 'XYZ' rpy-axes assignment only")
        c6 = ctypes.c_double * 6
        out = c6()
        self.lib.stew_inverse_ws(
            c6(*xsi), c6(*ysi), c6(*zsi), c6(*xmi), c6(*ymi), c6(*zmi),
            roll, pitch, yaw, px, py, pz, out,
        )
        return np.array(out[:])


def _library_candidates():
    base = "stew_inverse_ws"
    names = {
        "win32": [base + ".dll"],
        "darwin": ["lib" + base + ".dylib", base + ".dylib"],
    }.get(sys.platform, ["lib" + base + ".so", base + ".so"])
    # search next to the frozen exe, the native/ folder, and CWD
    roots = [os.path.dirname(os.path.abspath(sys.argv[0])),
             getattr(sys, "_MEIPASS", ""),
             os.path.join(os.path.dirname(__file__), "..", "native"),
             os.getcwd()]
    for r in roots:
        if not r:
            continue
        for nm in names:
            p = os.path.join(r, nm)
            if os.path.isfile(p):
                yield p


_C_KERNEL = None


def load_c_kernel(verbose=True):
    """Try to load the optional compiled kernel. Returns True if loaded."""
    global _C_KERNEL
    for path in _library_candidates():
        try:
            _C_KERNEL = _CKernel(path)
            if verbose:
                print(f"Fast C kernel loaded: {path}")
            return True
        except Exception as exc:        # pragma: no cover - depends on user build
            if verbose:
                print(f"Could not load C kernel at {path}: {exc}")
    if verbose:
        print("Using vectorised NumPy kernel (no compiled DLL found - this is "
              "already 25-50x faster than the MATLAB MEX build).")
    return False


def have_c_kernel():
    return _C_KERNEL is not None
