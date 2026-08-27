"""Embedded interactive 3D view of the hexapod (base, platform, legs, axes).

Port of draw_plat.m (static draw) and anim_plat.m (40-step animation).  Rendered
with matplotlib inside Qt so the mouse rotates it just like the MATLAB axes, and
so dashed legs / circular joint markers / axis-arrow labels match the original.
"""
from __future__ import annotations
import os
import numpy as np
import matplotlib
# Bind matplotlib's Qt backend to PySide6 (the shipped binding), not some
# other Qt binding that might also be present in the user's environment.
os.environ.setdefault("QT_API", "pyside6")
matplotlib.use("QtAgg")
from matplotlib.backends.backend_qtagg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
from PySide6.QtCore import QTimer, Qt
from PySide6.QtWidgets import QWidget, QVBoxLayout

from . import config

ARROW_LEN = 150.0
LINE_W = 2.0
N_STEPS = 40                       # animation frames (matches anim_plat.m)
# Automatic fit of the sketch: the magnification is chosen on every full
# redraw so that everything drawn (joints, legs, triad arrows and letters)
# fills the widget in the current view with this margin left free on the
# limiting side.  FIT_MARGIN_FRAC is a fraction of the widget's smaller side;
# FIT_MARGIN_PX (at 100 dpi) covers the arrow letters and joint markers, which
# extend past the geometric points.
FIT_MARGIN_FRAC = 0.05
FIT_MARGIN_PX = 20
FIT_ZOOM_MIN, FIT_ZOOM_MAX = 0.05, 20.0
LABEL_OFFSET = 0.28                # the axis letter sits this fraction of the arrow length
                                   # beyond the tip, along the arrow, clear of the arrowhead
DEFAULT_AZIM = -120.0              # MATLAB view([-30,20]) -> matplotlib azim = az-90
DEFAULT_ELEV = 20.0
BASE_EDGES = [(1, 2), (3, 4), (5, 0)]                       # 0-indexed (MATLAB 2-3,4-5,6-1)
PLAT_EDGES = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0)]


def draw_axes_triad(ax, color, labels=("X", "Y", "Z"), length=ARROW_LEN, fontsize=8,
                    directions=None):
    """Draw the coordinate triad (three arrows from the origin with a letter at
    each tip) on a 3D axes.  Shared by the main sketch and the Change-Coords
    dialog, so both show exactly the same triad.

    `directions` (optional) gives the unit vector each arrow points along, in
    the axes' own coordinates, for X, Y, Z in that order; default is +X, +Y,
    +Z.  The dialog uses it to draw a relabelled frame's positive axes where
    they physically point (a flipped axis points the opposite way) while the
    view stays the same."""
    if directions is None:
        directions = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
    a = length
    for lab, d in zip(labels, directions):
        d = np.asarray(d, float)
        tip = a * d
        ln, = ax.plot([0, tip[0]], [0, tip[1]], [0, tip[2]], "-", color=color, lw=1)
        cone = arrow_head(tip, d, a, color)
        # The data limits are set explicitly by the callers, so the cone must
        # not autoscale the axes (newer matplotlib pads a collection's faces
        # into one array and would autoscale on padding values).
        try:
            ax.add_collection3d(cone, autolim=False)
        except TypeError:
            ax.add_collection3d(cone)
        # letter centred on a point beyond the tip along the arrow, so it
        # never sits on the arrowhead whatever the view angle
        lp = tip + LABEL_OFFSET * a * d
        tx = ax.text(lp[0], lp[1], lp[2], lab, fontsize=fontsize, ha="center", va="center", color=color)
        # The only boundary of the sketch is the widget itself (see
        # PlatformView): no artist is clipped to the axes rectangle.
        for art in (ln, cone, tx):
            art.set_clip_on(False)


def arrow_head(tip, direction, length, color, n_sides=12):
    """A solid 3D cone whose apex is at `tip` and whose axis runs back along
    `direction` (unit vector): the arrowhead points in the arrow's own
    direction in every view, unlike a flat screen marker.  Cone height is
    12 % and base radius 4 % of the arrow length."""
    d = np.asarray(direction, float)
    d = d / (np.linalg.norm(d) or 1.0)
    h, r = 0.12 * length, 0.04 * length
    helper = np.array([1.0, 0.0, 0.0]) if abs(d[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    u = np.cross(d, helper); u /= np.linalg.norm(u)
    v = np.cross(d, u)
    apex = np.asarray(tip, float)
    centre = apex - h * d
    ang = np.linspace(0.0, 2.0 * np.pi, n_sides, endpoint=False)
    ring = [centre + r * (np.cos(t) * u + np.sin(t) * v) for t in ang]
    # every face is a triangle (sides from the apex, base fanned from its
    # centre) so the collection's face array is rectangular in every
    # matplotlib version
    faces = [[apex, ring[i], ring[(i + 1) % n_sides]] for i in range(n_sides)]
    faces += [[centre, ring[(i + 1) % n_sides], ring[i]] for i in range(n_sides)]
    poly = Poly3DCollection(np.array(faces, float), facecolors=color, edgecolors=color,
                            linewidths=0.3)
    return poly


def standard_display_frame(base_pts, plat_pts):
    """The sketch's standard display frame D (display = D @ p) chosen from the
    geometry itself, so the default view looks natural whatever the
    coordinate axes are:

      * screen "up" is the normal of the plane the joints lie in (least
        variance direction of all twelve joints, which is the common normal
        of parallel base and platform planes), oriented from the base
        centroid towards the platform centroid, so the base is below the
        platform;
      * screen "range" (the display X axis, drawn left to right) is the
        direction of greatest joint extent within that plane, with its sign
        chosen so that the mechanism lies on its positive side, i.e. the
        coordinate triad points downrange, towards the mechanism;
      * the third display axis completes a right-handed set.

    Returns a proper rotation (det +1).  Degenerate inputs fall back to the
    identity.  Deterministic for a given geometry, and invariant to a
    relabelling of the coordinate axes or a change of origin (the physical
    picture is the same, so the same D M^T results)."""
    P = np.vstack([np.asarray(base_pts, float), np.asarray(plat_pts, float)])
    if P.shape != (12, 3) or not np.all(np.isfinite(P)):
        return np.eye(3)
    c_all = P.mean(axis=0)
    Q = P - c_all
    scale = float(np.max(np.abs(Q))) or 1.0
    try:
        _, sing, vt = np.linalg.svd(Q / scale, full_matrices=True)
    except np.linalg.LinAlgError:
        return np.eye(3)
    if sing[0] < 1e-9 or sing[1] < 1e-9 * sing[0]:
        return np.eye(3)                       # all joints on a line or a point
    up = vt[2]                                  # least-variance direction (plane normal)
    sep = np.asarray(plat_pts, float).mean(axis=0) - np.asarray(base_pts, float).mean(axis=0)
    if np.dot(up, sep) < 0:
        up = -up
    rng = vt[0] - np.dot(vt[0], up) * up        # greatest extent, within the plane
    n = np.linalg.norm(rng)
    if n < 1e-9:
        return np.eye(3)
    rng /= n
    proj = np.dot(c_all, rng)                   # mechanism centroid relative to the origin
    if abs(proj) > 1e-6 * scale:
        if proj < 0:
            rng = -rng
    elif rng[int(np.argmax(np.abs(rng)))] < 0:  # centred on the origin: keep a positive sense
        rng = -rng
    side = np.cross(up, rng)                    # rng x side = up
    D = np.vstack([rng, side, up])
    if np.linalg.det(D) < 0:                    # cannot happen for the construction above
        D[1] = -D[1]
    return D


# The sketch shows the standard frame turned 180 degrees about the vertical
# (the triad points the other way, away from the viewer's left); the 3D
# workspace windows use the unturned standard frame.  SKETCH_TURN is its own
# inverse, so the workspace frame is SKETCH_TURN @ sketch frame.
SKETCH_TURN = np.diag([-1.0, -1.0, 1.0])


class TriadPairView(QWidget):
    """Two copies of the sketch's coordinate triad, fixed in the sketch's
    nominal (reset) view: the current X, Y, Z on the left and, after an arrow,
    the NEW frame's positive X, Y, Z drawn where they physically point in that
    same view (a current axis mapped to a negative new axis makes the new
    arrow point the opposite way).  The view cannot be rotated or zoomed by
    the user here; only the arrows change.  Used by the Change-Coords dialog."""

    def __init__(self, parent=None, fg="black"):
        super().__init__(parent)
        self.fig = Figure(figsize=(4.6, 1.5))
        self.canvas = FigureCanvas(self.fig)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.addWidget(self.canvas)
        self.setAttribute(Qt.WA_TranslucentBackground, True)
        self.setAutoFillBackground(False)
        self.canvas.setAttribute(Qt.WA_TranslucentBackground, True)
        self.canvas.setAutoFillBackground(False)
        self.canvas.setStyleSheet("background: transparent;")
        self._fg = fg
        self.ax_cur = self.fig.add_subplot(121, projection="3d")
        self.ax_new = self.fig.add_subplot(122, projection="3d")
        # Fixed at the sketch's nominal (reset) view: no mouse rotation or
        # zoom here; only the letters and arrows of the "New" triad change.
        for ax in (self.ax_cur, self.ax_new):
            try:
                ax.disable_mouse_rotation()
            except Exception:
                pass
        self.canvas.setEnabled(False)          # no pointer interaction at all
        self._dirs = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
        self.redraw(self._dirs)

    def redraw(self, new_directions):
        """new_directions: for the new X, Y, Z axes in turn, the unit vector
        each points along expressed in the CURRENT axes (the rows of the
        relabelling matrix M, since new_j = M[j, :] . current)."""
        self._dirs = tuple(tuple(float(c) for c in d) for d in new_directions)
        self.fig.patch.set_facecolor("none")
        self.fig.patch.set_alpha(0.0)
        for ax, dirs, title in ((self.ax_cur, ((1, 0, 0), (0, 1, 0), (0, 0, 1)), "Current"),
                                (self.ax_new, self._dirs, "New")):
            ax.cla()
            ax.set_axis_off()
            ax.view_init(elev=DEFAULT_ELEV, azim=DEFAULT_AZIM)
            ax.patch.set_facecolor("none")
            ax.patch.set_alpha(0.0)
            draw_axes_triad(ax, self._fg, ("X", "Y", "Z"), length=1.0, fontsize=11,
                            directions=dirs)
            # symmetric limits so a reversed arrow has the same room as a
            # forward one; the same limits on both triads keep the view identical
            lim = 1.0 + LABEL_OFFSET + 0.2          # room for the letters beyond the tips
            ax.set_xlim(-lim, lim); ax.set_ylim(-lim, lim); ax.set_zlim(-lim, lim)
            try:
                ax.set_box_aspect((1, 1, 1), zoom=1.45)   # fill the small panel
            except TypeError:
                try:
                    ax.set_box_aspect((1, 1, 1))
                except Exception:
                    pass
            except Exception:
                pass
            ax.set_title(title, fontsize=9, color=self._fg, pad=2)
        for t in list(self.fig.texts):
            t.remove()
        self.fig.text(0.5, 0.5, "\u2192", fontsize=26, ha="center", va="center", color=self._fg)
        self.fig.subplots_adjust(left=0.02, right=0.98, top=0.88, bottom=0.0, wspace=0.2)
        self.canvas.draw_idle()


class PlatformView(QWidget):
    _fit_margin_frac = FIT_MARGIN_FRAC     # fit margins (the export renderer uses smaller ones)
    _fit_margin_px = FIT_MARGIN_PX

    def __init__(self, parent=None):
        super().__init__(parent)
        # Same proportions as config.PLOT_RECT_MATLAB (478 x 285 px at 100 dpi);
        # no figure margins, so the equal-aspect drawing is centred in the
        # widget.  Matplotlib keeps a 3D axes' box aspect by shrinking the
        # axes rectangle to a square inside the figure and clips line artists
        # to that square (text is never clipped), which would cut the legs off
        # short of the widget edge: every artist the sketch draws therefore has
        # clipping turned off, so the widget rectangle is the only boundary.
        self.fig = Figure(figsize=(4.78, 2.85))
        self.fig.subplots_adjust(left=0, right=1, bottom=0, top=1)
        self.canvas = FigureCanvas(self.fig)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.addWidget(self.canvas)

        # Transparent background so the plot blends into the window instead of
        # sitting in an opaque white box that covers the controls behind it.
        self.setAttribute(Qt.WA_TranslucentBackground, True)
        self.setAutoFillBackground(False)
        self.canvas.setAttribute(Qt.WA_TranslucentBackground, True)
        self.canvas.setAutoFillBackground(False)
        self.canvas.setStyleSheet("background: transparent;")

        self.ax = self.fig.add_subplot(111, projection="3d")
        self.ax.set_axis_off()
        # MATLAB view([-30,20]) -> matplotlib azim = az-90 = -120, elev = 20.
        self.ax.view_init(elev=DEFAULT_ELEV, azim=DEFAULT_AZIM)
        self._fg = "black"          # axis-arrow / label colour (white in dark themes)
        self._apply_transparency()
        # Sketch display frame: points are plotted as D @ p and the triad shows
        # where the coordinate axes point (the columns of D).  D is chosen
        # from the geometry (SKETCH_TURN @ standard_display_frame) on the first
        # draw, so the default view is the natural one; a "Change Coords."
        # relabelling and an origin change both keep the drawing still with
        # D <- D M^T (apply_axis_map): only the triad follows the frame, and
        # the drawing is refitted.  Not stored in formdata.txt.
        self._disp = np.eye(3)
        self._auto_frame = True

        self._base = np.zeros((6, 3))        # display-frame points (D @ p)
        self._plat = np.zeros((6, 3))
        self._raw_base = np.zeros((6, 3))    # the same points as given (current axes)
        self._raw_plat = np.zeros((6, 3))
        self._leg_lines = []
        self._plat_lines = []
        self._base_lines = []

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._anim_tick)
        self._anim_start = None
        self._anim_end = None
        self._anim_i = 0
        self._first = True

    # ------------------------------------------------------------------
    def _apply_transparency(self):
        """Keep the figure/axes backgrounds fully transparent (must be re-applied
        after every ax.cla(), which resets the axes facecolor to white)."""
        self.fig.patch.set_facecolor("none")
        self.fig.patch.set_alpha(0.0)
        self.ax.patch.set_facecolor("none")
        self.ax.patch.set_alpha(0.0)
        try:
            for axis in (self.ax.xaxis, self.ax.yaxis, self.ax.zaxis):
                axis.pane.set_alpha(0.0)
                axis.pane.fill = False
        except Exception:
            pass

    # ------------------------------------------------------------------
    def _set_equal_aspect(self, pts):
        """Equal-aspect cube of data limits enclosing `pts` (display frame)."""
        lo = pts.min(axis=0)
        hi = pts.max(axis=0)
        ctr = 0.5 * (lo + hi)
        rng = float(np.max(hi - lo)) * 0.5 + 1e-6
        self.ax.set_xlim(ctr[0] - rng, ctr[0] + rng)
        self.ax.set_ylim(ctr[1] - rng, ctr[1] + rng)
        self.ax.set_zlim(ctr[2] - rng, ctr[2] + rng)

    def _set_zoom(self, zoom):
        """Magnify the drawing about the cube centre without changing the data
        limits (nothing is clipped: see the clip_on notes above)."""
        try:
            self.ax.set_box_aspect((1, 1, 1), zoom=zoom)
            return True
        except TypeError:                 # matplotlib < 3.6: no zoom keyword
            try:
                self.ax.set_box_aspect((1, 1, 1))
            except Exception:
                pass
        except Exception:
            pass
        return False

    def _project_px(self, pts):
        """Pixel positions of 3D points under the axes' current projection
        (the same transform the artists use when drawn)."""
        M = self.ax.get_proj()
        vec = np.vstack([np.asarray(pts, float).T, np.ones(len(pts))])
        res = M @ vec
        w = np.where(np.abs(res[3]) < 1e-12, 1e-12, res[3])
        xy = np.column_stack([res[0] / w, res[1] / w])
        return self.ax.transData.transform(xy)

    def _fit_view(self, pts):
        """Centre and size the drawing in the widget for the current view angle.

        `pts` are the joints, the origin and the triad tips (display frame).
        Two things are adjusted, both without touching the view angle:
          * pan: the centre of the equal-aspect data cube is moved so that the
            projected bounding box of `pts` is centred in the widget (a 3D
            move is solved from the numeric Jacobian of the projection at the
            cube centre, so the shift lies in the screen plane);
          * zoom: the magnification is set so that box fills the widget with
            FIT_MARGIN_FRAC of the smaller side plus FIT_MARGIN_PX (room for
            the arrow letters and markers) left free on the limiting side.
        The projection is perspective, so a few measure-and-correct
        iterations are used; each projects a dozen points and the loop
        converges in two to four steps.  Deterministic for a given geometry,
        view angle and widget size, and cheap enough for every full redraw
        (start-up, Reset View, origin or axis change, theme change)."""
        if not self._set_zoom(1.0):
            return
        self.ax.apply_aspect()            # axes rectangle as it will be drawn
        fw, fh = float(self.fig.bbox.width), float(self.fig.bbox.height)
        if fw <= 0 or fh <= 0:
            return
        scale = self.fig.dpi / 100.0
        margin = self._fit_margin_frac * min(fw, fh) + self._fit_margin_px * scale
        avail = np.array([max(fw / 2.0 - margin, 1.0), max(fh / 2.0 - margin, 1.0)])
        ax_bbox = self.ax.bbox
        centre_px = np.array([0.5 * (ax_bbox.x0 + ax_bbox.x1), 0.5 * (ax_bbox.y0 + ax_bbox.y1)])
        pts = np.asarray(pts, float)
        zoom = 1.0
        for _ in range(8):
            px = self._project_px(pts)
            lo, hi = px.min(axis=0), px.max(axis=0)
            half = np.maximum(0.5 * (hi - lo), 1e-9)
            offset = 0.5 * (lo + hi) - centre_px
            factor = float(np.min(avail / half))
            if np.all(np.abs(offset) < 0.5) and abs(factor - 1.0) < 0.01:
                break
            # pan: move the cube centre by the 3D step whose projection is `offset`
            c = np.array([np.mean(self.ax.get_xlim3d()), np.mean(self.ax.get_ylim3d()),
                          np.mean(self.ax.get_zlim3d())])
            rng = 0.5 * (self.ax.get_xlim3d()[1] - self.ax.get_xlim3d()[0])
            eps = max(rng * 1e-3, 1e-9)
            base = self._project_px(c[None, :])[0]
            J = np.column_stack([(self._project_px((c + eps * e)[None, :])[0] - base) / eps
                                 for e in np.eye(3)])
            delta, *_ = np.linalg.lstsq(J, offset, rcond=None)
            if not np.all(np.isfinite(delta)):
                break
            step = float(np.linalg.norm(delta))
            if step > 4.0 * rng:                # never let a bad step run away
                delta *= 4.0 * rng / step
            c = c + delta
            if not np.all(np.isfinite(c)):
                break
            self.ax.set_xlim3d(c[0] - rng, c[0] + rng)
            self.ax.set_ylim3d(c[1] - rng, c[1] + rng)
            self.ax.set_zlim3d(c[2] - rng, c[2] + rng)
            # zoom about the (new) cube centre
            zoom = float(np.clip(zoom * factor, FIT_ZOOM_MIN, FIT_ZOOM_MAX))
            self._set_zoom(zoom)
            self.ax.apply_aspect()

    def _edge_lw(self):
        """Line width of the base / platform edges (the export sketch halves it)."""
        return LINE_W

    def _edge_alpha(self):
        return 1.0

    def _draw_axes_arrows(self):
        D = self._disp
        draw_axes_triad(self.ax, self._fg, directions=(D[:, 0], D[:, 1], D[:, 2]))

    def apply_axis_map(self, M):
        """Keep the drawing where it is after the axes were relabelled with
        new = M @ current: display = D_old @ current = D_old @ M^T @ new."""
        self._disp = self._disp @ np.asarray(M, float).T
        self._auto_frame = False

    def set_auto_frame(self):
        """Choose the standard display frame from the geometry on the next
        full redraw (start-up)."""
        self._auto_frame = True

    def workspace_frame(self):
        """The frame the 3D workspace windows are viewed through: the sketch's
        frame without the 180 degree turn."""
        return SKETCH_TURN @ np.asarray(self._disp, float)

    def _to_display(self, pts):
        return np.asarray(pts, float) @ self._disp.T

    def set_theme_color(self, color):
        """Set the origin-arrow / XYZ-label colour (e.g. white on a dark theme)
        and redraw so the axes are always readable against the background."""
        color = "white" if str(color).lower() in ("white", "#ffffff", "#fff") else (
                "black" if str(color).lower() in ("black", "#000000", "#000") else color)
        if color == self._fg:
            return
        self._fg = color
        if not self._first:
            self.draw_static(self._raw_base, self._raw_plat)

    def reset_view(self):
        """Reset the embedded sketch to its default view angle + magnification."""
        self._timer.stop()
        self.ax.view_init(elev=DEFAULT_ELEV, azim=DEFAULT_AZIM)
        if not self._first:
            self.draw_static(self._raw_base, self._raw_plat)   # re-applies default zoom too
        else:
            self.canvas.draw_idle()

    # ------------------------------------------------------------------
    def draw_static(self, base_pts, plat_pts):
        """Full redraw (equivalent to draw_plat.m)."""
        self._timer.stop()
        # Remember the current view angle so a redraw (pose change / theme change)
        # keeps the user's mouse rotation instead of snapping back to default.
        try:
            cur_elev, cur_azim = float(self.ax.elev), float(self.ax.azim)
        except Exception:
            cur_elev, cur_azim = DEFAULT_ELEV, DEFAULT_AZIM
        self._raw_base = np.asarray(base_pts, float).copy()
        self._raw_plat = np.asarray(plat_pts, float).copy()
        if self._auto_frame:
            self._disp = SKETCH_TURN @ standard_display_frame(self._raw_base, self._raw_plat)
            self._auto_frame = False
        self._base = self._to_display(base_pts)
        self._plat = self._to_display(plat_pts)
        self.ax.cla()
        self.ax.set_axis_off()
        self.ax.view_init(elev=cur_elev, azim=cur_azim)
        self._apply_transparency()
        self._draw_axes_arrows()

        # base triangle edges (dark blue)
        self._base_lines = []
        for i1, i2 in BASE_EDGES:
            ln, = self.ax.plot(self._base[[i1, i2], 0], self._base[[i1, i2], 1],
                               self._base[[i1, i2], 2], "-", lw=self._edge_lw(), color=config.BASE_COLOR,
                               alpha=self._edge_alpha())
            ln.set_clip_on(False)
            self._base_lines.append(ln)

        # legs base->platform (first dash-dot, rest solid), coloured
        self._leg_lines = []
        for i in range(6):
            style = "-." if i == 0 else "-"
            ln, = self.ax.plot([self._base[i, 0], self._plat[i, 0]],
                               [self._base[i, 1], self._plat[i, 1]],
                               [self._base[i, 2], self._plat[i, 2]],
                               style, marker="o", ms=3, lw=LINE_W, color=config.LEG_COLORS[i])
            ln.set_clip_on(False)
            self._leg_lines.append(ln)

        # platform hexagon edges (dark red)
        self._plat_lines = []
        for i1, i2 in PLAT_EDGES:
            ln, = self.ax.plot(self._plat[[i1, i2], 0], self._plat[[i1, i2], 1],
                               self._plat[[i1, i2], 2], "-", lw=self._edge_lw(), color=config.PLAT_COLOR,
                               alpha=self._edge_alpha())
            ln.set_clip_on(False)
            self._plat_lines.append(ln)

        allpts = np.vstack([self._base, self._plat, [[0, 0, 0]],
                            (1.0 + LABEL_OFFSET) * ARROW_LEN * self._disp.T])   # the letter positions
        self._set_equal_aspect(allpts)
        self._fit_view(allpts)
        if self._first:
            self._first = False
        self.canvas.draw_idle()

    # ------------------------------------------------------------------
    def update_pose(self, base_pts, plat_pts, animate=True):
        """Move to a new platform pose, animating over N_STEPS frames if asked."""
        if self._first or not self._leg_lines or not animate:
            self.draw_static(base_pts, plat_pts)
            return
        self._raw_base = np.asarray(base_pts, float).copy()
        self._raw_plat = np.asarray(plat_pts, float).copy()
        base_pts = self._to_display(base_pts)
        plat_pts = self._to_display(plat_pts)
        self._base = base_pts
        self._anim_start = self._plat.copy()
        self._anim_end = plat_pts.copy()
        self._anim_i = 0
        self._timer.start(16)        # ~60 fps

    def _anim_tick(self):
        self._anim_i += 1
        t = self._anim_i / N_STEPS
        cur = self._anim_start + (self._anim_end - self._anim_start) * t
        # update legs
        for i, ln in enumerate(self._leg_lines):
            ln.set_data_3d([self._base[i, 0], cur[i, 0]],
                           [self._base[i, 1], cur[i, 1]],
                           [self._base[i, 2], cur[i, 2]])
        # update base edges (base may have moved)
        for (i1, i2), ln in zip(BASE_EDGES, self._base_lines):
            ln.set_data_3d(self._base[[i1, i2], 0], self._base[[i1, i2], 1], self._base[[i1, i2], 2])
        # update platform edges
        for (i1, i2), ln in zip(PLAT_EDGES, self._plat_lines):
            ln.set_data_3d(cur[[i1, i2], 0], cur[[i1, i2], 1], cur[[i1, i2], 2])
        self.canvas.draw_idle()
        if self._anim_i >= N_STEPS:
            self._timer.stop()
            self._plat = self._anim_end.copy()


# ---------------------------------------------------------------------------
# Off-screen rendering of the sketch (exports)
# ---------------------------------------------------------------------------
class SketchDrawing:
    """The drawing part of PlatformView (display frame, fit, artists) as a
    plain class, so the same code can render off screen without a widget."""


for _name in ("_set_equal_aspect", "_set_zoom", "_project_px", "_fit_view", "_draw_axes_arrows",
              "apply_axis_map", "set_auto_frame", "workspace_frame", "_to_display", "draw_static",
              "_apply_transparency", "_edge_lw", "_edge_alpha"):
    setattr(SketchDrawing, _name, PlatformView.__dict__[_name])


class _NoTimer:
    def stop(self):
        pass


class OffscreenSketch(SketchDrawing):
    """PlatformView's drawing on an Agg figure of the given size (inches, dpi),
    black on white, standard frame and default view, fitted with a small
    margin.  The base and platform edges are drawn at half width and 30 %
    opacity so the legs stand out; the legs are as in the window."""

    _fit_margin_frac = 0.02        # tighter fit than the window: less white around the drawing
    _fit_margin_px = 10

    def _edge_lw(self):
        return 0.5 * LINE_W

    def _edge_alpha(self):
        return 0.3

    def __init__(self, width_in, height_in, dpi=200):
        from matplotlib.backends.backend_agg import FigureCanvasAgg
        self.fig = Figure(figsize=(width_in, height_in), dpi=dpi)
        self.fig.subplots_adjust(left=0, right=1, bottom=0, top=1)
        self.canvas = FigureCanvasAgg(self.fig)
        self.ax = self.fig.add_subplot(111, projection="3d")
        self.ax.set_axis_off()
        self.ax.view_init(elev=DEFAULT_ELEV, azim=DEFAULT_AZIM)
        self._fg = "black"
        self._disp = np.eye(3)
        self._auto_frame = True
        self._base = np.zeros((6, 3)); self._plat = np.zeros((6, 3))
        self._raw_base = np.zeros((6, 3)); self._raw_plat = np.zeros((6, 3))
        self._leg_lines = []; self._plat_lines = []; self._base_lines = []
        self._timer = _NoTimer()
        self._first = True
        self._anim_start = None; self._anim_end = None; self._anim_i = 0

    def render_rgba(self, base_pts, plat_pts, frame=None):
        """Draw the joints and return an RGBA array on a white background.
        `frame` (3 x 3) fixes the display frame instead of deriving it from the
        geometry, so several previews can share one orientation."""
        if frame is not None:
            self._disp = np.asarray(frame, float)
            self._auto_frame = False
        self.draw_static(base_pts, plat_pts)
        self.fig.patch.set_facecolor("white")
        self.fig.patch.set_alpha(1.0)
        self.canvas.draw()
        return np.asarray(self.canvas.buffer_rgba()).copy()


def render_sketch_rgba(base_pts, plat_pts, width_in, height_in, dpi=200, frame=None):
    """The main window's sketch for the given joints as an RGBA image (white
    background) for the exports: in the standard view derived from the
    geometry, or in the given display frame."""
    return OffscreenSketch(width_in, height_in, dpi).render_rgba(base_pts, plat_pts, frame=frame)


def sketch_frame_for_origin(base1, plat1, R_o):
    """Display frame for a preview in origin o's coordinates that shows the
    mechanism exactly as the primary-origin preview does: the standard frame
    of the primary-origin geometry (turned like the window) times R_o, since
    q_1 = R_o q_o + d_o."""
    D1 = SKETCH_TURN @ standard_display_frame(base1, plat1)
    return D1 @ np.asarray(R_o, float)

