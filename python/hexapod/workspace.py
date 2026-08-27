"""Reachable and orientation workspace solvers.

Faithful (but fully vectorised) port of draw_reachable_workspace_spherical.m and
draw_orientation_workspace_spherical.m.  The maths is identical to the original
spherical-sweep + radial-bisection method; the only difference is that every
search direction is processed simultaneously with NumPy array operations instead
of a per-direction Python/MATLAB loop, which makes it 25-50x faster than the
MATLAB+MEX build while producing the same boundary points.

Datasets are saved as .npz (NEW) and can be recalled from either .npz or the
original MATLAB .mat files (NEW/RECALL workflow preserved).
"""
from __future__ import annotations
import os
import time
import numpy as np

from .kinematics import _rotation, legs_for_directions, rpy_perm
from . import config


# ---------------------------------------------------------------------------
# Direction grid (same nested ordering as the MATLAB theta/phi loops)
# ---------------------------------------------------------------------------
def _direction_grid(scaler):
    d_theta = 1.0 * scaler * np.pi / 180.0
    d_phi = 0.25 * scaler * np.pi / 180.0
    n_theta = int(np.ceil(np.pi / d_theta))
    dirs = []
    for k in range(n_theta + 1):
        theta = min(k * d_theta, np.pi)
        st, ct = np.sin(theta), np.cos(theta)
        phi = 0.0
        # phi : 0 : d_phi : 2*pi - d_phi   (exclusive upper bound, like MATLAB)
        while phi < 2 * np.pi - d_phi + 1e-12:
            dirs.append((st * np.cos(phi), st * np.sin(phi), ct))
            phi += d_phi
    return np.asarray(dirs, float)


def _grid_shape(scaler):
    """Return (n_rows, n_phi) of the direction grid for a given scaler, matching
    the exact nested loop in _direction_grid (n_rows = n_theta+1 theta rings,
    each with the same n_phi azimuth samples)."""
    d_theta = 1.0 * scaler * np.pi / 180.0
    d_phi = 0.25 * scaler * np.pi / 180.0
    n_theta = int(np.ceil(np.pi / d_theta))
    n_phi = 0
    phi = 0.0
    while phi < 2 * np.pi - d_phi + 1e-12:
        n_phi += 1
        phi += d_phi
    return n_theta + 1, n_phi


def structured_mesh(data, max_vertices=1_200_000):
    """Build a clean closed surface mesh directly from the spherical search grid.

    Because every (theta, phi) direction yields exactly one boundary point, the
    points form a structured sphere-topology grid.  Connecting neighbouring grid
    nodes into triangles (wrapping in phi) gives an artifact-free closed shell at
    ANY resolution - unlike a generic alpha-shape, which produces spurious
    'curtain' faces on sparse clouds.  For very fine grids the grid is uniformly
    strided down to <= max_vertices so rendering stays fast; the FULL cloud is
    still used elsewhere for the reported limits.

    Returns (vertices Nx3, faces (M,3) int) or None if the data isn't a grid that
    matches its stored scaler (e.g. an externally-produced .mat) - callers then
    fall back to the alpha-shape.
    """
    scaler = float(np.ravel(data.get("scaler", 0.0))[0]) if "scaler" in data else 0.0
    if scaler <= 0:
        return None
    n_rows, n_phi = _grid_shape(scaler)
    pts, _ = dataset_points(data)
    if len(pts) != n_rows * n_phi:
        return None                      # not a recognised full grid -> fallback
    grid = pts.reshape(n_rows, n_phi, 3)

    # uniform stride so the rendered mesh stays under the vertex cap
    total = n_rows * n_phi
    if total > max_vertices:
        f = (total / max_vertices) ** 0.5
        rs = max(1, int(np.ceil(f)))
        cs = max(1, int(np.ceil(f)))
        ri = np.unique(np.r_[np.arange(0, n_rows, rs), n_rows - 1])   # keep both poles
        ci = np.arange(0, n_phi, cs)
        grid = grid[np.ix_(ri, ci)]
    R, P = grid.shape[0], grid.shape[1]
    verts = grid.reshape(-1, 3)

    # triangle connectivity between ring r and r+1, wrapping phi (col P-1 -> 0)
    r = np.arange(R - 1)[:, None]
    c = np.arange(P)[None, :]
    v00 = (r * P + c).ravel()
    v01 = (r * P + (c + 1) % P).ravel()
    v10 = ((r + 1) * P + c).ravel()
    v11 = ((r + 1) * P + (c + 1) % P).ravel()
    faces = np.empty((v00.size * 2, 3), np.int64)
    faces[0::2, 0] = v00; faces[0::2, 1] = v10; faces[0::2, 2] = v11
    faces[1::2, 0] = v00; faces[1::2, 1] = v11; faces[1::2, 2] = v01
    return verts, faces


# ---------------------------------------------------------------------------
# Core vectorised sweep: returns boundary radii for every direction
# ---------------------------------------------------------------------------
def _sweep_radii(a, b, R, center, n, r_init, leg_lo, leg_hi, zpd,
                 tol_r=0.0005, progress=None, cancelled=None, label="workspace"):
    """Bracket-and-bisect the boundary radius for every direction at once.

    a,b : (6,3) base/platform joints; R,center : centre-pose rotation/translation
    n   : (N,3) unit directions; r_init : scalar initial bracket
    Returns r_lo (N,) boundary radius per direction.
    """
    N = len(n)
    center = np.asarray(center, float)

    def violates(radii):
        legs = legs_for_directions(a, b, R, center, n, radii) - zpd
        return np.any((legs > leg_hi) | (legs < leg_lo), axis=1)

    # --- bracket: grow r_hi (doubling) until each direction first violates ---
    r_lo = np.zeros(N)
    r_hi = np.full(N, float(r_init))
    active = np.ones(N, bool)
    for it in range(64):
        if not active.any():
            break
        if cancelled and cancelled():
            return None
        v = violates(r_hi)
        grow = active & ~v          # still inside -> push the bracket out
        r_lo[grow] = r_hi[grow]
        r_hi[grow] *= 2.0
        active = grow
        if progress and it % 4 == 0:
            inside = int(active.sum())
            progress(f"... bracketing {label}: {N - inside:,}/{N:,} directions bounded")

    # --- bisection to tolerance (vectorised) ---
    for it in range(60):
        if np.all((r_hi - r_lo) <= tol_r):
            break
        if cancelled and cancelled():
            return None
        rm = 0.5 * (r_lo + r_hi)
        v = violates(rm)
        r_hi = np.where(v, rm, r_hi)
        r_lo = np.where(v, r_lo, rm)
        if progress and it % 3 == 0:
            width = float(np.max(r_hi - r_lo))
            progress(f"... refining {label}: bisection pass {it + 1}, max bracket {width:.3f}")
    return r_lo


def _split_upper_lower(coord_along_axis, center_value):
    """Replicate the MATLAB 'firstLower' contiguous split: everything before the
    first point that drops below the centre plane is 'upper', the rest 'lower'."""
    below = np.nonzero(coord_along_axis < center_value)[0]
    if below.size == 0:
        return np.arange(len(coord_along_axis)), np.array([], int)
    first = below[0]
    return np.arange(first), np.arange(first, len(coord_along_axis))


# ---------------------------------------------------------------------------
# Public solvers
# ---------------------------------------------------------------------------
def reachable_sweep(geom, limits, center, scaler, progress=None, cancelled=None):
    """Compute the reachable (XYZ translation) workspace boundary.

    geom   : dict with xsi,ysi,zsi,xmi,ymi,zmi (per-joint coordinates),zpd,leg_lo,leg_hi,
             rpy_axes (which axis roll / pitch / yaw rotate about, default 'XYZ')
    limits : dict with pxmin,pxmax,pymin,pymax,pzmin,pzmax
    center : (roll0,pitch0,yaw0,x0,y0,z0) centre pose
    Returns a dict of arrays ready to save / render, or None if cancelled.
    """
    t0 = time.time()
    if progress:
        progress("Working on reachable workspace...")
    roll0, pitch0, yaw0, x0, y0, z0 = center
    a = np.column_stack([geom["xsi"], geom["ysi"], geom["zsi"]])
    b = np.column_stack([geom["xmi"], geom["ymi"], geom["zmi"]])
    R = _rotation(roll0, pitch0, yaw0, geom.get("rpy_axes", "XYZ"))
    c = np.array([x0, y0, z0], float)

    dx = max(abs(limits["pxmin"] - x0), abs(limits["pxmax"] - x0))
    dy = max(abs(limits["pymin"] - y0), abs(limits["pymax"] - y0))
    dz = max(abs(limits["pzmin"] - z0), abs(limits["pzmax"] - z0))
    r_init = float(np.sqrt(dx * dx + dy * dy + dz * dz))

    n = _direction_grid(scaler)
    N = len(n)
    CHUNK = config.SWEEP_CHUNK
    n_chunks = (N + CHUNK - 1) // CHUNK
    if progress:
        progress(f"... solving {N:,} directions in {n_chunks} chunk(s)...")
    r = np.empty(N)
    for s in range(0, N, CHUNK):
        if cancelled and cancelled():
            return None
        e = min(s + CHUNK, N)
        # Let a single-chunk run show the detailed bracket/bisect messages;
        # for multi-chunk runs report progress at chunk granularity instead.
        pcb = progress if (progress and n_chunks == 1) else None
        rc = _sweep_radii(a, b, R, c, n[s:e], r_init, geom["leg_lo"], geom["leg_hi"],
                          geom["zpd"], progress=pcb, cancelled=cancelled, label="reachable")
        if rc is None:
            return None
        r[s:e] = rc
        if progress and n_chunks > 1:
            progress(f"... reachable: {e:,}/{N:,} directions solved")

    pts = c[None, :] + r[:, None] * n          # absolute boundary points (N,3)
    wx, wy, wz = pts[:, 0], pts[:, 1], pts[:, 2]
    Zc = 0.5 * (wz.max() + wz.min())
    up, dn = _split_upper_lower(wz, Zc)

    data = {
        "kind": "reachable",
        "w_x_u": wx[up] - x0, "w_y_u": wy[up] - y0, "w_z_u": wz[up] - z0,
        "w_x_d": wx[dn] - x0, "w_y_d": wy[dn] - y0, "w_z_d": wz[dn] - z0,
        "scaler": float(scaler),
    }
    if progress:
        _report_limits(progress, data, kind="reachable")
        progress(f"...Total elapsed time: {_mmss(time.time() - t0)} ...")
    return data


def _orientation_radii(a, b, base_t, n, r_init, leg_lo, leg_hi, zpd,
                       roll0, pitch0, yaw0, tol_r=0.0005, cancelled=None, axes="XYZ"):
    """Bracket-and-bisect the boundary radius for a chunk of angular directions.

    Each direction perturbs (roll0,pitch0,yaw0); position is fixed at base_t.
    `axes` is the rpy-axes assignment: R = P R0 P^T (see kinematics._rotation).
    Returns r_lo (len(n),) or None if cancelled.
    """
    ang0 = np.array([roll0, pitch0, yaw0])
    P = rpy_perm(axes)
    identity_axes = str(axes).upper() == "XYZ"

    def legs_for_angles(radii):
        m = len(radii)
        ang = ang0[None, :] + radii[:, None] * n
        tx, ty, tz = np.radians(ang[:, 0]), np.radians(ang[:, 1]), np.radians(ang[:, 2])
        cx, sx = np.cos(tx), np.sin(tx); cy, sy = np.cos(ty), np.sin(ty); cz, sz = np.cos(tz), np.sin(tz)
        R = np.empty((m, 3, 3))
        R[:, 0, 0] = cy * cz;                 R[:, 0, 1] = -cy * sz;                R[:, 0, 2] = sy
        R[:, 1, 0] = sx * sy * cz + cx * sz;  R[:, 1, 1] = -sx * sy * sz + cx * cz; R[:, 1, 2] = -sx * cy
        R[:, 2, 0] = -cx * sy * cz + sx * sz; R[:, 2, 1] = cx * sy * sz + sx * cz;  R[:, 2, 2] = cx * cy
        if not identity_axes:
            R = np.einsum("ij,njk,lk->nil", P, R, P)          # P R0 P^T
        b_trans = np.einsum("nij,kj->nki", R, b) + base_t[None, None, :]
        return np.sqrt(np.sum((a[None, :, :] - b_trans) ** 2, axis=2))

    def violates(radii):
        legs = legs_for_angles(radii) - zpd
        return np.any((legs > leg_hi) | (legs < leg_lo), axis=1)

    N = len(n)
    r_lo = np.zeros(N); r_hi = np.full(N, r_init); active = np.ones(N, bool)
    for _ in range(64):
        if not active.any():
            break
        if cancelled and cancelled():
            return None
        v = violates(r_hi)
        grow = active & ~v
        r_lo[grow] = r_hi[grow]; r_hi[grow] *= 2.0; active = grow
    for _ in range(60):
        if np.all((r_hi - r_lo) <= tol_r):
            break
        if cancelled and cancelled():
            return None
        rm = 0.5 * (r_lo + r_hi)
        v = violates(rm)
        r_hi = np.where(v, rm, r_hi); r_lo = np.where(v, r_lo, rm)
    return r_lo


def orientation_sweep(geom, limits, center, scaler, progress=None, cancelled=None):
    """Compute the orientation (roll/pitch/yaw) workspace boundary."""
    t0 = time.time()
    if progress:
        progress("working on orientation workspace...")
    roll0, pitch0, yaw0, x0, y0, z0 = center
    a = np.column_stack([geom["xsi"], geom["ysi"], geom["zsi"]])
    b = np.column_stack([geom["xmi"], geom["ymi"], geom["zmi"]])

    # In orientation space the "direction" perturbs (roll,pitch,yaw); position is fixed.
    n = _direction_grid(scaler)
    r_init = float(max(limits["rollmax"] - roll0, roll0 - limits["rollmin"],
                       limits["pitchmax"] - pitch0, pitch0 - limits["pitchmin"],
                       limits["yawmax"] - yaw0, yaw0 - limits["yawmin"]))

    base_t = np.array([x0, y0, z0], float)
    leg_lo, leg_hi, zpd = geom["leg_lo"], geom["leg_hi"], geom["zpd"]

    N = len(n)
    CHUNK = config.SWEEP_CHUNK
    n_chunks = (N + CHUNK - 1) // CHUNK
    if progress:
        progress(f"... solving {N:,} directions in {n_chunks} chunk(s)...")
    r_lo = np.empty(N)
    for s in range(0, N, CHUNK):
        if cancelled and cancelled():
            return None
        e = min(s + CHUNK, N)
        rc = _orientation_radii(a, b, base_t, n[s:e], r_init, leg_lo, leg_hi, zpd,
                                roll0, pitch0, yaw0, cancelled=cancelled,
                                axes=geom.get("rpy_axes", "XYZ"))
        if rc is None:
            return None
        r_lo[s:e] = rc
        if progress:
            progress(f"... orientation: {e:,}/{N:,} directions solved")

    ang = np.array([roll0, pitch0, yaw0])[None, :] + r_lo[:, None] * n
    wr, wp, wy_ = ang[:, 0], ang[:, 1], ang[:, 2]
    up, dn = _split_upper_lower(wy_ - yaw0, 0.0)   # split on delta-yaw < 0

    data = {
        "kind": "orientation",
        "w_roll_u": wr[up] - roll0, "w_pitch_u": wp[up] - pitch0, "w_yaw_u": wy_[up] - yaw0,
        "w_roll_d": wr[dn] - roll0, "w_pitch_d": wp[dn] - pitch0, "w_yaw_d": wy_[dn] - yaw0,
        "scaler": float(scaler),
    }
    if progress:
        _report_limits(progress, data, kind="orientation")
        progress(f"...Total elapsed time: {_mmss(time.time() - t0)} ...")
    return data


# ---------------------------------------------------------------------------
# Helpers to assemble points / limits from a dataset (NEW or RECALL)
# ---------------------------------------------------------------------------
def dataset_points(data):
    """Return (all_points Nx3, (x_limits, y_limits, z_limits)) for a dataset."""
    if data["kind"] == "reachable":
        xu, yu, zu = data["w_x_u"], data["w_y_u"], data["w_z_u"]
        xd, yd, zd = data["w_x_d"], data["w_y_d"], data["w_z_d"]
    else:
        xu, yu, zu = data["w_roll_u"], data["w_pitch_u"], data["w_yaw_u"]
        xd, yd, zd = data["w_roll_d"], data["w_pitch_d"], data["w_yaw_d"]
    ax = np.concatenate([np.ravel(xu), np.ravel(xd)])
    ay = np.concatenate([np.ravel(yu), np.ravel(yd)])
    az = np.concatenate([np.ravel(zu), np.ravel(zd)])
    pts = np.column_stack([ax, ay, az])
    lims = ((ax.min(), ax.max()), (ay.min(), ay.max()), (az.min(), az.max()))
    return pts, lims


def dataset_view_frame(data):
    """The 3 x 3 display frame stored with a dataset (see the main window's
    sweep set-up): the 3D windows are viewed through it so their "up" matches
    the sketch.  Identity for datasets without one (older files, external
    .mat files) or with an invalid one."""
    v = data.get("view_frame") if hasattr(data, "get") else None
    if v is None:
        return np.eye(3)
    try:
        D = np.asarray(v, float).reshape(3, 3)
    except Exception:
        return np.eye(3)
    if not np.all(np.isfinite(D)) or abs(np.linalg.det(D) - 1.0) > 1e-6:
        return np.eye(3)
    return D


def dataset_origin_name(data):
    """Return the origin / point-of-interest name stored with a dataset, or
    None for datasets that predate the origin feature (or external .mat files).
    Robust to the string having gone through .npz or .mat round-trips."""
    v = data.get("origin_name") if hasattr(data, "get") else None
    if v is None:
        return None
    try:
        arr = np.asarray(v)
        if arr.dtype.kind in ("U", "S"):
            s = str(arr.ravel()[0]) if arr.size else ""
        else:
            s = str(v)
    except Exception:
        s = str(v)
    s = s.strip()
    return s or None


def _report_limits(progress, data, kind):
    _, (xl, yl, zl) = dataset_points(data)
    if kind == "reachable":
        progress("Reachable workspace limits:")
        progress(f"X -> [{xl[0]:.3f}, {xl[1]:.3f}]mm")
        progress(f"Y -> [{yl[0]:.3f}, {yl[1]:.3f}]mm")
        progress(f"Z -> [{zl[0]:.3f}, {zl[1]:.3f}]mm")
    else:
        progress("Orientation workspace limits:")
        progress(f"Roll  -> [{xl[0]:.3f}, {xl[1]:.3f}] deg")
        progress(f"Pitch -> [{yl[0]:.3f}, {yl[1]:.3f}] deg")
        progress(f"Yaw   -> [{zl[0]:.3f}, {zl[1]:.3f}] deg")


def _mmss(seconds):
    return f"{int(seconds // 60):02d}:{seconds % 60:06.3f}"


# ---------------------------------------------------------------------------
# Persistence: NEW (.npz) save, and load from .npz or original MATLAB .mat
# ---------------------------------------------------------------------------
def save_dataset(path, data):
    """Save a workspace dataset.

    If `path` ends in .mat the file is written in MATLAB format with the same
    variable names the original tool used (so the files are interchangeable with
    MATLAB and with the original .m exporters); otherwise a compressed .npz is
    written.
    """
    arrays = {k: np.asarray(v) for k, v in data.items() if k != "kind"}
    ext = os.path.splitext(path)[1].lower()
    if ext == ".mat":
        from scipy.io import savemat
        # store as row vectors / scalar, like MATLAB's save()
        out = {}
        for k, v in arrays.items():
            if k == "scaler":
                out[k] = float(np.ravel(v)[0]) if np.ndim(v) else float(v)
            elif v.dtype.kind in ("U", "S"):
                out[k] = str(np.ravel(v)[0]) if v.size else ""   # e.g. origin_name, rpy_axes
            elif k == "view_frame":
                out[k] = np.asarray(v, float).reshape(3, 3)      # keep the matrix shape
            else:
                out[k] = np.ravel(v).reshape(1, -1)
        savemat(path, out)
    else:
        np.savez_compressed(path, **arrays, kind=data["kind"])


def load_dataset(path):
    """Load a dataset from .npz or a MATLAB .mat (v7 via scipy, v7.3 via h5py)."""
    ext = os.path.splitext(path)[1].lower()
    if ext == ".npz":
        z = np.load(path, allow_pickle=True)
        out = {k: z[k] for k in z.files}
        out["kind"] = str(out.get("kind", "reachable"))
        return out
    # MATLAB .mat
    try:
        from scipy.io import loadmat
        m = loadmat(path)
        return _mat_to_dataset({k: v for k, v in m.items() if not k.startswith("__")})
    except NotImplementedError:
        import h5py        # v7.3 (HDF5) fallback
        out = {}
        with h5py.File(path, "r") as f:
            for k in f.keys():
                out[k] = np.array(f[k]).squeeze()
        return _mat_to_dataset(out)


def _mat_to_dataset(m):
    keys = set(m.keys())
    if {"w_x_u", "w_y_u", "w_z_u"} <= keys:
        kind = "reachable"
    else:
        kind = "orientation"
    out = {k: np.ravel(np.asarray(v)) for k, v in m.items()}
    if "view_frame" in m:
        out["view_frame"] = np.asarray(m["view_frame"], float).reshape(3, 3)
    out["kind"] = kind
    if "scaler" in m:
        out["scaler"] = float(np.ravel(m["scaler"])[0])
    return out


# ---------------------------------------------------------------------------
# Alpha-shape surface (SciPy fallback; the app normally uses PyVista's
# delaunay_3d(alpha=...) which gives the same alpha-ball surface).
# ---------------------------------------------------------------------------
def alpha_surface(points, alpha):
    """Return (vertices, triangle_faces) of the alpha-shape boundary surface.

    Equivalent to MATLAB alphaShape + boundaryFacets: keep tetrahedra whose
    circumradius <= alpha, then take the faces that belong to exactly one kept
    tetra (the outer boundary).
    """
    from scipy.spatial import Delaunay
    P = np.asarray(points, float)
    tri = Delaunay(P)
    tetra = tri.simplices
    A = P[tetra]                                  # (M,4,3)
    a0 = A[:, 0, :]
    M = 2.0 * (A[:, 1:, :] - a0[:, None, :])      # (M,3,3)
    rhs = np.sum(A[:, 1:, :] ** 2 - a0[:, None, :] ** 2, axis=2)   # (M,3)
    R = np.full(len(tetra), np.inf)
    det = np.linalg.det(M)
    ok = np.abs(det) > 1e-9
    if ok.any():
        c = np.linalg.solve(M[ok], rhs[ok][..., None])[..., 0]
        R[ok] = np.linalg.norm(c - a0[ok], axis=1)
    keep = R <= alpha

    from collections import defaultdict
    count = defaultdict(int)
    for t in tetra[keep]:
        for f in ((t[0], t[1], t[2]), (t[0], t[1], t[3]),
                  (t[0], t[2], t[3]), (t[1], t[2], t[3])):
            count[tuple(sorted(f))] += 1
    faces = np.array([f for f, n in count.items() if n == 1], int)
    return P, faces
