"""Secondary dialogs.

- AdjustDialog          : the "+/-" column offset tool (openAdjustDlg.m / applyAdjust.m)
- WorkspaceProgressDialog: resolution + pose picker with a scrolling status log
- PngExportDialog       : NEW/RECALL source + number-of-images (yes_callback.m)
- OriginDialog          : origins / points of interest list (origin_dialog.m)
- AxisMapDialog         : "Change Coords." right-handed axis relabelling (change_coords_dialog.m)
- IncrementalAdjDialog  : "Incremental Adj. Table" per-origin, per-axis leg ratios (incremental_adj_table.m)
- quit_dialog()         : Quit with / without saving / Cancel
"""
from __future__ import annotations
import os
import numpy as np
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QFont, QFontMetrics, QPen, QColor, QPalette
from PySide6.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QGridLayout, QLabel, QLineEdit,
    QPushButton, QRadioButton, QButtonGroup, QTextEdit, QMessageBox, QWidget,
    QTableWidget, QTableWidgetItem, QComboBox, QCheckBox, QFileDialog, QFrame, QHeaderView,
    QStyledItemDelegate, QLayout, QSpacerItem, QSizePolicy, QRadioButton, QButtonGroup,
)

from . import config
from . import settings_io
from . import kinematics
from .widgets import NumberLineEdit, IntLineEdit, NameLineEdit
from . import adj_table
from . import savedir


# ---------------------------------------------------------------------------
# Column adjust ("+/-") dialog
# ---------------------------------------------------------------------------
class AdjustDialog(QDialog):
    """Add or subtract one value from all six joints of a coordinate column.

    Faithful port of openAdjustDlg.m / applyAdjust.m: a single numeric entry plus
    an "Update ZPD" button. The running total (cumulative across openings) is kept
    by the caller and shown here. The entered value is read from `.value` after
    the dialog is accepted; the caller applies it to the six fields and
    re-solves.  Works for the X, Y and Z columns of both joint tables."""

    def __init__(self, field, prev_total=0.0, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Adjust ZPD")
        self._value = 0.0

        axis_char = field[0].upper()                       # X, Y or Z
        prefix = "platform" if field.endswith("mi") else "base"

        lay = QVBoxLayout(self)
        msg = QLabel(f"Add or subtract {axis_char} value from all "
                     f"{prefix} ({field}) joints:")
        msg.setAlignment(Qt.AlignHCenter)
        lay.addWidget(msg)

        total = QLabel(f"Total offset so far: {prev_total:.3f} mm")
        total.setAlignment(Qt.AlignHCenter)
        f = total.font(); f.setItalic(True); total.setFont(f)
        lay.addWidget(total)

        row = QHBoxLayout()
        row.addStretch(1)
        self.entry = NumberLineEdit("0.000")           # standard copy / paste, 3 decimals
        self.entry.setFixedWidth(150)
        self.entry.setAlignment(Qt.AlignHCenter)
        row.addWidget(self.entry)
        row.addStretch(1)
        lay.addLayout(row)

        btn_row = QHBoxLayout()
        btn_row.addStretch(1)
        self.update_btn = QPushButton("Update ZPD")
        self.cancel_btn = QPushButton("Cancel")
        btn_row.addWidget(self.update_btn)
        btn_row.addWidget(self.cancel_btn)
        lay.addLayout(btn_row)

        self.update_btn.clicked.connect(self._on_update)
        self.cancel_btn.clicked.connect(self.reject)

    def _on_update(self):
        try:
            self._value = float(self.entry.text())
        except ValueError:
            QMessageBox.warning(self, "Invalid Input", "Please enter a numeric value.")
            return
        self.accept()

    @property
    def value(self):
        return self._value


# ---------------------------------------------------------------------------
# Workspace progress dialog (resolution + pose + scrolling status)
# ---------------------------------------------------------------------------
class WorkspaceProgressDialog(QDialog):
    """Pick resolution + starting pose and watch progress.

    Emits run_requested(scaler, pose_key, is_recall).  pose_key in
    {"home","new","old"}.  The owner runs the solver in a worker thread and feeds
    text back via append_status()."""
    run_requested = Signal(float, str, bool)
    cancel_requested = Signal()

    HIGH = config.SCALER_HIGH
    MEDIUM = config.SCALER_MEDIUM
    LOW = config.SCALER_LOW
    RECALL = config.SCALER_RECALL

    def __init__(self, title="Workspace", parent=None):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.resize(460, 380)
        lay = QVBoxLayout(self)

        lay.addWidget(QLabel("Select pose to start analysis at:"))
        pose_row = QHBoxLayout()
        self.pose_group = QButtonGroup(self)
        self.rb_home = QRadioButton("Home")
        self.rb_new = QRadioButton("New pose")
        self.rb_old = QRadioButton("Old pose")
        self.rb_home.setChecked(True)
        for rb in (self.rb_home, self.rb_new, self.rb_old):
            self.pose_group.addButton(rb)
            pose_row.addWidget(rb)
        lay.addLayout(pose_row)

        lay.addWidget(QLabel("Resolution:   (Low = quick preview \u2192 High = finest)"))
        res_row = QGridLayout()
        self.btn_high = QPushButton("High \u2014 finest")
        self.btn_med = QPushButton("Medium")
        self.btn_low = QPushButton("Low \u2014 fastest")
        self.btn_recall = QPushButton("Recall saved data")
        res_row.addWidget(self.btn_high, 0, 0)
        res_row.addWidget(self.btn_med, 0, 1)
        res_row.addWidget(self.btn_low, 1, 0)
        res_row.addWidget(self.btn_recall, 1, 1)
        res_row.setColumnStretch(0, 1)          # equal-width columns
        res_row.setColumnStretch(1, 1)
        lay.addLayout(res_row)

        lay.addWidget(QLabel("Status:"))
        self.status = QTextEdit()
        self.status.setReadOnly(True)
        lay.addWidget(self.status, 1)

        bottom = QHBoxLayout()
        bottom.addStretch(1)
        self.abort_btn = QPushButton("Abort")
        self.abort_btn.setEnabled(False)            # only active while a run is live
        self.abort_btn.setToolTip("Stop the current workspace analysis")
        self.cancel_btn = QPushButton("Close")
        bottom.addWidget(self.abort_btn)
        bottom.addWidget(self.cancel_btn)
        lay.addLayout(bottom)

        # Fixed button heights so the layout is identical in every colour theme
        # (a themed stylesheet changes button padding; a native button doesn't -
        # pinning the height keeps everything in the same place across themes).
        for b in (self.btn_high, self.btn_med, self.btn_low, self.btn_recall):
            b.setFixedHeight(32)
        for b in (self.abort_btn, self.cancel_btn):
            b.setFixedHeight(28)

        self.btn_high.clicked.connect(lambda: self._go(self.HIGH, False))
        self.btn_med.clicked.connect(lambda: self._go(self.MEDIUM, False))
        self.btn_low.clicked.connect(lambda: self._go(self.LOW, False))
        self.btn_recall.clicked.connect(lambda: self._go(self.RECALL, True))
        self.abort_btn.clicked.connect(self._on_abort)
        self.cancel_btn.clicked.connect(self._on_cancel)

    def _pose_key(self):
        if self.rb_new.isChecked():
            return "new"
        if self.rb_old.isChecked():
            return "old"
        return "home"

    def _go(self, scaler, is_recall):
        self._set_buttons(False)
        self.abort_btn.setEnabled(not is_recall)    # recall is instant; nothing to abort
        self.run_requested.emit(scaler, self._pose_key(), is_recall)

    def _on_abort(self):
        """Halt the running sweep but keep the dialog open so it can be re-run."""
        self.append_status("aborting current analysis...")
        self.abort_btn.setEnabled(False)
        self.cancel_requested.emit()

    def _on_cancel(self):
        self.cancel_requested.emit()
        self.reject()

    def _set_buttons(self, enabled):
        for b in (self.btn_high, self.btn_med, self.btn_low, self.btn_recall):
            b.setEnabled(enabled)

    def append_status(self, text):
        """Prepend newest-first, like the MATLAB status box."""
        for line in str(text).splitlines():
            if line.strip():
                self.status.insertPlainText("")
                cursor_text = line + "\n" + self.status.toPlainText()
                self.status.setPlainText(cursor_text)

    def finished_run(self):
        self._set_buttons(True)
        self.abort_btn.setEnabled(False)


# ---------------------------------------------------------------------------
# PNG export dialog
# ---------------------------------------------------------------------------
class PngExportDialog(QDialog):
    """Choose NEW vs RECALL source and number of images (1-360)."""

    def __init__(self, parent=None, has_new=True):
        super().__init__(parent)
        self.setWindowTitle("Export Workspace to PNG")
        lay = QVBoxLayout(self)

        lay.addWidget(QLabel("Data source:"))
        src_row = QHBoxLayout()
        self.group = QButtonGroup(self)
        self.rb_new = QRadioButton("NEW (most recent)")
        self.rb_recall = QRadioButton("RECALL (load file)")
        self.group.addButton(self.rb_new)
        self.group.addButton(self.rb_recall)
        if has_new:
            self.rb_new.setChecked(True)
        else:
            self.rb_recall.setChecked(True)
            self.rb_new.setEnabled(False)
        src_row.addWidget(self.rb_new)
        src_row.addWidget(self.rb_recall)
        lay.addLayout(src_row)

        n_row = QHBoxLayout()
        n_row.addWidget(QLabel("Number of images (1-360):"))
        self.n_images = IntLineEdit("1", lo=1, hi=360)
        n_row.addWidget(self.n_images)
        lay.addLayout(n_row)

        note = QLabel("1 = a single still image of the current view. "
                      "N = N images taken at evenly spaced angles around a full "
                      "360\u00b0 turn (for assembling a rotation/turntable animation).")
        note.setWordWrap(True)
        nf = note.font(); nf.setPointSize(8); nf.setItalic(True); note.setFont(nf)
        note.setStyleSheet("color:#888888;")
        lay.addWidget(note)

        btn_row = QHBoxLayout()
        btn_row.addStretch(1)
        self.ok = QPushButton("Export")
        self.cancel = QPushButton("Cancel")
        for b in (self.ok, self.cancel):
            b.setFixedHeight(28)            # theme-independent height
        btn_row.addWidget(self.ok)
        btn_row.addWidget(self.cancel)
        lay.addLayout(btn_row)

        self.ok.clicked.connect(self._validate_accept)
        self.cancel.clicked.connect(self.reject)

    def _validate_accept(self):
        try:
            n = int(self.n_images.text())
        except ValueError:
            n = 0
        if not (1 <= n <= 360):
            QMessageBox.warning(self, "Invalid number",
                                "Please enter a whole number of images between 1 and 360.")
            return
        self.accept()

    @property
    def use_recall(self):
        return self.rb_recall.isChecked()

    @property
    def count(self):
        return int(self.n_images.text())


# ---------------------------------------------------------------------------
# Origins / points of interest dialog
# ---------------------------------------------------------------------------
class OriginDialog(QDialog):
    """Choose, add, rename, re-offset or delete origins (points of interest).

    Application-modal: every other program window is blocked until Confirm or
    Cancel.  Rows are plain widgets on the dialog background (no console-style
    text box): a radio button (exactly one selected), the name (up to
    config.ORIGIN_NAME_MAX
    characters, no apostrophe) and the X / Y / Z offset of the point from
    Origin 1, in the Origin 1 frame [mm].  Origin 1 is the reference: its
    offset is locked at zero and it cannot be deleted.

    Nothing is applied here.  On Confirm the validated list is available as
    `.origins` and the 1-based selection as `.active`; the owner does the frame
    change.  Cancel leaves the caller's state untouched.
    """
    NAME_MAX = config.ORIGIN_NAME_MAX
    MAX_ROWS = config.MAX_ORIGINS
    ROW_H = 26
    NAME_W = 178
    OFF_W = 74
    KEYS = ("dx", "dy", "dz", "roll", "pitch", "yaw")   # the six value columns
    DLG_W = 740              # fixed width; the height follows the row count
    BTN_H = 28               # same fixed button height as the other dialogs

    def __init__(self, origins, active, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Origins / Points of Interest")
        self.setWindowModality(Qt.ApplicationModal)
        self.setModal(True)
        self._rows = []              # dicts: radio, name, dx, dy, dz, roll, pitch, yaw
        self._result_origins = None
        self._result_active = None

        lay = QVBoxLayout(self)
        lay.setSpacing(8)

        intro = QLabel(
            "Select the origin (point of interest) that the 6-DOF pose, the "
            "System Illustration and the workspace analyses are referenced to. "
            "An origin is a frame: its X, Y, Z offset [mm] and its roll, pitch, "
            "yaw orientation [\u00b0] relative to Origin 1, both measured in the "
            "Origin 1 frame (angles about the current roll / pitch / yaw axes).")
        intro.setWordWrap(True)
        lay.addWidget(intro)
        self._intro = intro

        # header + rows live in one grid (inside a plain container widget on
        # the dialog background) so the columns line up exactly.  The container
        # is rebuilt whole after a delete, which keeps the grid dense.
        self._table_row = QHBoxLayout()               # table + stretch -> rows hug the left
        self._table_row.addStretch(1)
        lay.addLayout(self._table_row)
        self.table = None
        self.grid = None
        self._new_table()

        self.group = QButtonGroup(self)
        self.group.setExclusive(True)
        self.group.buttonToggled.connect(self._on_selection_changed)

        add_row = QHBoxLayout()
        self.add_btn = QPushButton("Add New Origin / Point of Interest")
        self.del_btn = QPushButton("Delete Selected")
        self.del_btn.setToolTip("Remove the origin whose radio button is selected "
                                "(Origin 1 is the reference and cannot be deleted)")
        add_row.addWidget(self.add_btn)
        add_row.addWidget(self.del_btn)
        add_row.addStretch(1)
        lay.addLayout(add_row)

        note = QLabel("Confirm re-expresses every joint coordinate, the old and new "
                      "poses, the illustration and all later workspace analyses about "
                      "the selected origin. Cancel changes nothing.")
        note.setWordWrap(True)
        nf = note.font(); nf.setPointSize(8); nf.setItalic(True); note.setFont(nf)
        note.setStyleSheet("color:#888888;")
        lay.addWidget(note)
        self._note = note

        btn_row = QHBoxLayout()
        btn_row.addStretch(1)
        self.ok = QPushButton("Confirm")
        self.cancel = QPushButton("Cancel")
        btn_row.addWidget(self.ok)
        btn_row.addWidget(self.cancel)
        lay.addLayout(btn_row)

        # Fixed button heights so the layout is identical in every colour theme
        # (same convention as the other dialogs).  Enter in any box confirms;
        # the other buttons must be clicked explicitly.
        for b in (self.add_btn, self.del_btn, self.ok, self.cancel):
            b.setFixedHeight(self.BTN_H)
            b.setAutoDefault(False)
        self.ok.setDefault(True)

        self.add_btn.clicked.connect(lambda: self._add_row())
        self.del_btn.clicked.connect(self._delete_selected)
        self.ok.clicked.connect(self._validate_accept)
        self.cancel.clicked.connect(self.reject)

        origins, active = settings_io.normalise_origins(origins, active)
        for o in origins:
            self._add_row(o["name"], [o[k] for k in self.KEYS], select=False)
        self._rows[active - 1]["radio"].setChecked(True)
        self._refresh_buttons()
        self._fit_height()

    # ------------------------------------------------------------------
    def _new_table(self):
        """Create (or replace) the container that holds the header and rows."""
        if self.table is not None:
            self._table_row.removeWidget(self.table)
            self.table.setParent(None)
            self.table.deleteLater()
        self.table = QWidget()
        self.table.setAutoFillBackground(False)         # same background as the dialog
        self.grid = QGridLayout(self.table)
        self.grid.setContentsMargins(0, 0, 0, 0)
        self.grid.setHorizontalSpacing(8)
        self.grid.setVerticalSpacing(4)
        self.grid.setColumnMinimumWidth(0, 22)
        for col, text in ((1, f"Name (max {self.NAME_MAX} chars)"), (2, "X [mm]"), (3, "Y [mm]"),
                          (4, "Z [mm]"), (5, "Roll [\u00b0]"), (6, "Pitch [\u00b0]"),
                          (7, "Yaw [\u00b0]")):
            h = QLabel(text)
            hf = h.font(); hf.setBold(True); h.setFont(hf)
            h.setAlignment(Qt.AlignHCenter | Qt.AlignVCenter)
            self.grid.addWidget(h, 0, col)
        self._table_row.insertWidget(0, self.table)
        self._ensure_shown([self.table])
        self._rows = []

    def _ensure_shown(self, widgets):
        """Widgets added to a layout while the dialog is already visible are only
        shown later (Qt queues a deferred show), and until then the layout
        treats them as hidden and gives them zero height.  Showing them right
        here makes the height calculation below see the true row count."""
        if not self.isVisible():
            return
        for w in widgets:
            w.show()

    def _num_edit(self, value, locked):
        # `value` is a number, or the raw text of an existing box when rows are
        # rebuilt after a delete (so half-typed entries are never reformatted)
        e = NumberLineEdit(value if isinstance(value, str) else f"{float(value):.3f}")
        e.setAlignment(Qt.AlignHCenter)
        e.setFixedWidth(self.OFF_W)
        e.setFixedHeight(self.ROW_H - 4)
        if locked:
            e.setReadOnly(True)
            e.setToolTip("Origin 1 is the reference frame: its offset and orientation "
                         "are always zero")
            e.setStyleSheet("QLineEdit{color:#7A7A7A;}")
        return e

    def _add_row(self, name=None, values=None, select=True):
        """values: the six numbers (dx, dy, dz, roll, pitch, yaw), or the raw
        text of existing boxes when rows are rebuilt after a delete."""
        if len(self._rows) >= self.MAX_ROWS:
            return
        idx = len(self._rows)
        is_ref = idx == 0
        if name is None:
            name = config.DEFAULT_ORIGIN_NAME if is_ref else f"Origin {idx + 1}"

        radio = QRadioButton()
        radio.setToolTip("Use this origin for the pose, illustration and workspaces")
        radio.setFixedHeight(self.ROW_H - 4)
        self.group.addButton(radio, idx)

        # any character except the apostrophe, which delimits the name in
        # formdata.txt; pastes are cleaned and truncated (see widgets.py)
        name_edit = NameLineEdit(name, max_len=self.NAME_MAX, forbidden="'")
        name_edit.setFixedWidth(self.NAME_W)
        name_edit.setFixedHeight(self.ROW_H - 4)
        if is_ref:
            name_edit.setToolTip("Reference origin (base/platform joints are entered "
                                 "in this frame). It can be renamed but not deleted.")

        if values is None:
            values = [0.0] * 6
        edits = [self._num_edit(v, is_ref) for v in values]

        r = idx + 1                       # grid row (row 0 is the header)
        self.grid.addWidget(radio, r, 0, Qt.AlignHCenter | Qt.AlignVCenter)
        self.grid.addWidget(name_edit, r, 1)
        for c, e in enumerate(edits):
            self.grid.addWidget(e, r, 2 + c)
        self.grid.setRowMinimumHeight(r, self.ROW_H)
        self._ensure_shown([radio, name_edit] + edits)

        row = dict(radio=radio, name=name_edit)
        row.update(zip(self.KEYS, edits))
        self._rows.append(row)
        if select:
            radio.setChecked(True)
            name_edit.setFocus()
            name_edit.selectAll()
        self._refresh_buttons()
        self._fit_height()

    def _selected_index(self):
        for i, row in enumerate(self._rows):
            if row["radio"].isChecked():
                return i
        return 0

    def _delete_selected(self):
        i = self._selected_index()
        if i == 0 or len(self._rows) <= 1:
            return                                   # Origin 1 is never deleted
        # Rebuild from the surviving rows' raw text so the grid rows / ids stay
        # dense and nothing the user typed is reformatted or lost.
        data = [(r["name"].text(), [r[k].text() for k in self.KEYS]) for r in self._rows]
        del data[i]
        for row in self._rows:
            self.group.removeButton(row["radio"])
        self._new_table()                                # drops every old row widget
        for name, vals in data:
            self._add_row(name, vals, select=False)
        self._rows[max(0, i - 1)]["radio"].setChecked(True)   # select the row above
        self._refresh_buttons()
        self._fit_height()

    def _on_selection_changed(self, *_):
        self._refresh_buttons()

    def _refresh_buttons(self):
        self.del_btn.setEnabled(self._selected_index() != 0 and len(self._rows) > 1)
        full = len(self._rows) >= self.MAX_ROWS
        self.add_btn.setEnabled(not full)
        self.add_btn.setToolTip(f"Maximum of {self.MAX_ROWS} origins reached" if full
                                else "Add a new point of interest (frame relative to Origin 1)")

    def _fit_height(self):
        """Size the window so every row is comfortably visible (grows / shrinks
        with the list; the width stays put).

        Deterministic by construction: the two word-wrapped labels are given a
        fixed height for the known content width (a QLabel's own heightForWidth
        is exact), every row widget and button has a fixed height, and the
        header row is pinned to ROW_H, so the total is a plain sum.  It is
        summed by hand here and cross-checked against the layout's size hint;
        the larger of the two is used, so a row can never be squeezed."""
        lay = self.layout()
        m = lay.contentsMargins()
        content_w = self.DLG_W - m.left() - m.right()
        label_h = {}
        for lbl in (self._intro, self._note):
            lbl.setFixedWidth(content_w)
            label_h[lbl] = max(int(lbl.heightForWidth(content_w)), 1)
            lbl.setFixedHeight(label_h[lbl])
        self.grid.setRowMinimumHeight(0, self.ROW_H)          # header row
        lay.activate()
        self.setMinimumSize(0, 0)
        self.setMaximumSize(16777215, 16777215)

        n_rows = len(self._rows)
        grid_h = (n_rows + 1) * self.ROW_H + n_rows * max(self.grid.verticalSpacing(), 0)
        blocks = [label_h[self._intro], grid_h, self.BTN_H, label_h[self._note], self.BTN_H]
        manual = m.top() + m.bottom() + sum(blocks) + max(lay.spacing(), 0) * (len(blocks) - 1)
        h = max(int(lay.sizeHint().height()), int(manual))
        self.setFixedSize(self.DLG_W, h)

    # ------------------------------------------------------------------
    def _collect_raw(self):
        out = []
        for i, row in enumerate(self._rows):
            def num(e):
                try:
                    return float(e.text())
                except ValueError:
                    return float("nan")
            entry = dict(name=row["name"].text())
            for k in self.KEYS:
                entry[k] = 0.0 if i == 0 else num(row[k])
            out.append(entry)
        return out

    def _validate_accept(self):
        raw = self._collect_raw()
        for i, o in enumerate(raw):
            if not o["name"].strip():
                QMessageBox.warning(self, "Missing name",
                                    f"Row {i + 1}: please enter an origin name "
                                    f"(1 to {self.NAME_MAX} characters).")
                self._rows[i]["name"].setFocus()
                return
            if len(o["name"].strip()) > self.NAME_MAX:
                QMessageBox.warning(self, "Name too long",
                                    f"Row {i + 1}: names are limited to "
                                    f"{self.NAME_MAX} characters.")
                self._rows[i]["name"].setFocus()
                return
            for key in self.KEYS:
                if o[key] != o[key]:                  # NaN -> unparsable
                    what = f"{key[1].upper()} offset" if key.startswith("d") else key
                    QMessageBox.warning(self, "Invalid value",
                                        f"Row {i + 1}: the {what} must be a number.")
                    self._rows[i][key].setFocus()
                    return
        origins, active = settings_io.normalise_origins(raw, self._selected_index() + 1)
        self._result_origins = origins
        self._result_active = active
        self.accept()

    @property
    def origins(self):
        return self._result_origins

    @property
    def active(self):
        return self._result_active


# ---------------------------------------------------------------------------
# Change Coords. dialog (right-handed axis relabelling)
# ---------------------------------------------------------------------------
class AxisMapDialog(QDialog):
    """Choose a new right-handed labelling of the X, Y, Z axes.

    Application-modal.  One row per CURRENT axis ("Current X ->", "Current Y
    ->", "Current Z ->") with six radio buttons (+X, -X, +Y, -Y, +Z, -Z);
    exactly one per row.  The right-hand rule is enforced downward:

      * changing the Current-X row disables, in the Current-Y row, the two
        choices parallel to it (and moves that row's selection to the next
        axis if it had become invalid), then
      * the Current-Z row is always the cross product of the two rows above
        (its only enabled choice), so every combination on screen is a proper
        right-handed rotation of the labels.  Changing the Current-Y row only
        updates the Current-Z row; rows above a change are never touched.

    Below the rows the sketch's coordinate triad is drawn twice in its default
    view: the current X, Y, Z and, after an arrow, the new frame's positive X,
    Y, Z pointing where they physically lie in that same view (a current axis
    mapped to a negative new axis makes the new arrow point the other way).
    The view itself is never changed.

    A second section assigns the rotation angles to axes: "Roll about", "Pitch
    about", "Yaw about" with X / Y / Z radios.  Only the right-handed cyclic
    assignments exist (XYZ, YZX, ZXY), enforced downward: the roll row is free,
    the pitch row is the next axis and the yaw row the one after (their only
    enabled choices).  The axes refer to the NEW labels chosen above.

    Confirm exposes `.mapping` (the three labels), `.matrix` and `.rpy_axes`;
    Close leaves everything untouched.
    """
    OPTIONS = config.AXIS_OPTIONS
    BTN_H = 28
    DLG_W = 520

    def __init__(self, parent=None, fg="black", rpy_axes="XYZ"):
        super().__init__(parent)
        self.setWindowTitle("Change Coordinate Axes")
        self.setWindowModality(Qt.ApplicationModal)
        self.setModal(True)
        self._mapping = None
        self._matrix = None
        self._rpy_axes = None
        self._rpy_initial = settings_io.normalise_rpy_axes(rpy_axes)

        lay = QVBoxLayout(self)
        lay.setSpacing(8)
        intro = QLabel(
            "Relabel the coordinate axes. For each current axis choose the signed "
            "axis it becomes; the combination is kept right-handed automatically "
            "(the Current Z row is always the cross product of the two rows above "
            "it). Confirm remaps every joint coordinate, the old and new poses, the "
            "search limits, the origins and the illustration. The field labels in "
            "the program stay X, Y, Z.")
        intro.setWordWrap(True)
        lay.addWidget(intro)
        self._intro = intro

        grid = QGridLayout()
        grid.setHorizontalSpacing(10)
        grid.setVerticalSpacing(6)
        self.groups = []
        self.radios = []                       # [row][option] -> QRadioButton
        for r, axis in enumerate("XYZ"):
            lbl = QLabel(f"Current {axis}  \u2192")
            f = lbl.font(); f.setBold(True); lbl.setFont(f)
            grid.addWidget(lbl, r, 0, Qt.AlignRight | Qt.AlignVCenter)
            grp = QButtonGroup(self)
            grp.setExclusive(True)
            row = []
            for c, opt in enumerate(self.OPTIONS):
                rb = QRadioButton(opt.replace("-", "\u2212"))
                grp.addButton(rb, c)
                grid.addWidget(rb, r, c + 1)
                row.append(rb)
            grp.buttonToggled.connect(lambda btn, on, rr=r: self._on_row_changed(rr) if on else None)
            self.groups.append(grp)
            self.radios.append(row)
        grid.setColumnStretch(len(self.OPTIONS) + 1, 1)
        lay.addLayout(grid)

        from .platform_view import TriadPairView
        self.triads = TriadPairView(self, fg=fg)
        self.triads.setFixedHeight(150)
        lay.addWidget(self.triads)

        # ---- rotation-angle axes ----
        rpy_intro = QLabel(
            "Rotation angles: choose the axis roll rotates about; pitch and yaw "
            "follow the right-hand rule (the next axes in cyclic order X, Y, Z). "
            "The axes are the new labels chosen above.")
        rpy_intro.setWordWrap(True)
        lay.addWidget(rpy_intro)
        self._rpy_intro = rpy_intro
        rgrid = QGridLayout()
        rgrid.setHorizontalSpacing(10)
        rgrid.setVerticalSpacing(6)
        self.rpy_groups = []
        self.rpy_radios = []                    # [angle][axis] -> QRadioButton
        for r, angle in enumerate(("Roll", "Pitch", "Yaw")):
            lbl = QLabel(f"{angle} about  \u2192")
            f = lbl.font(); f.setBold(True); lbl.setFont(f)
            rgrid.addWidget(lbl, r, 0, Qt.AlignRight | Qt.AlignVCenter)
            grp = QButtonGroup(self)
            grp.setExclusive(True)
            row = []
            for c, ch in enumerate("XYZ"):
                rb = QRadioButton(ch)
                grp.addButton(rb, c)
                rgrid.addWidget(rb, r, c + 1)
                row.append(rb)
            grp.buttonToggled.connect(lambda btn, on, rr=r: self._on_rpy_changed(rr) if on else None)
            self.rpy_groups.append(grp)
            self.rpy_radios.append(row)
        rgrid.setColumnStretch(4, 1)
        lay.addLayout(rgrid)

        note = QLabel("Close discards the selection and changes nothing.")
        nf = note.font(); nf.setPointSize(8); nf.setItalic(True); note.setFont(nf)
        note.setStyleSheet("color:#888888;")
        lay.addWidget(note)

        btn_row = QHBoxLayout()
        btn_row.addStretch(1)
        self.ok = QPushButton("Confirm")
        self.close_btn = QPushButton("Close")
        for b in (self.ok, self.close_btn):
            b.setFixedHeight(self.BTN_H)
            b.setAutoDefault(False)
        self.ok.setDefault(True)
        btn_row.addWidget(self.ok)
        btn_row.addWidget(self.close_btn)
        lay.addLayout(btn_row)
        self.ok.clicked.connect(self._confirm)
        self.close_btn.clicked.connect(self.reject)

        # identity mapping to start with (+X, +Y, +Z)
        self._updating = True
        self.radios[0][0].setChecked(True)
        self.radios[1][2].setChecked(True)
        self.radios[2][4].setChecked(True)
        self._updating = False
        self._enforce(from_row=0)
        # current angle assignment to start with
        self._updating = True
        self.rpy_radios[0]["XYZ".index(self._rpy_initial[0])].setChecked(True)
        self._updating = False
        self._enforce_rpy()

        m = lay.contentsMargins()
        content_w = self.DLG_W - m.left() - m.right()
        for lbl in (intro, rpy_intro):
            lbl.setFixedWidth(content_w)
            lbl.setFixedHeight(max(int(lbl.heightForWidth(content_w)), 1))
        lay.activate()
        self.setFixedSize(self.DLG_W, lay.sizeHint().height())

    # ------------------------------------------------------------------
    def _selected(self, row):
        idx = self.groups[row].checkedId()
        return self.OPTIONS[idx] if idx >= 0 else None

    def _select(self, row, label):
        self.radios[row][self.OPTIONS.index(label)].setChecked(True)

    def _on_row_changed(self, row):
        if self._updating:
            return
        self._enforce(from_row=row)

    def _enforce(self, from_row):
        """Re-establish the right-hand rule for the rows BELOW `from_row`."""
        self._updating = True
        try:
            vx = self._selected(0)
            if from_row <= 0:
                # Current-Y row: choices parallel to the Current-X choice are
                # impossible; if the current selection became parallel move it
                # to the next axis (cyclic X->Y->Z->X, positive sense).
                vy = self._selected(1)
                if vy is None or vy[1] == vx[1]:
                    nxt = "XYZ"[("XYZ".index(vx[1]) + 1) % 3]
                    vy = "+" + nxt
                    self._select(1, vy)
                for c, opt in enumerate(self.OPTIONS):
                    self.radios[1][c].setEnabled(opt[1] != vx[1])
            vy = self._selected(1)
            # Current-Z row: fully determined by the cross product.
            vz = kinematics.axis_label(np.cross(kinematics.axis_vector(vx),
                                                kinematics.axis_vector(vy)))
            self._select(2, vz)
            for c, opt in enumerate(self.OPTIONS):
                self.radios[2][c].setEnabled(opt == vz)
        finally:
            self._updating = False
        # rows of M are the current-frame directions of the new X, Y, Z axes
        M = kinematics.axis_map_matrix(self._selected(0), self._selected(1), self._selected(2))
        self.triads.redraw((M[0], M[1], M[2]))

    # ------------------------------------------------------------------
    def _rpy_selected(self, row):
        idx = self.rpy_groups[row].checkedId()
        return "XYZ"[idx] if idx >= 0 else None

    def _on_rpy_changed(self, row):
        if self._updating or row != 0:
            return
        self._enforce_rpy()

    def _enforce_rpy(self):
        """Pitch and yaw are the next axes after the roll axis, cyclically."""
        self._updating = True
        try:
            r = self._rpy_selected(0) or "X"
            k = "XYZ".index(r)
            for row, off in ((1, 1), (2, 2)):
                ch = "XYZ"[(k + off) % 3]
                self.rpy_radios[row]["XYZ".index(ch)].setChecked(True)
                for c in range(3):
                    self.rpy_radios[row][c].setEnabled("XYZ"[c] == ch)
        finally:
            self._updating = False

    def _confirm(self):
        labels = (self._selected(0), self._selected(1), self._selected(2))
        try:
            M = kinematics.axis_map_matrix(*labels)
        except ValueError:
            QMessageBox.warning(self, "Invalid mapping",
                                "The selected combination is not right-handed.")
            return
        rpy = "".join(self._rpy_selected(r) or "X" for r in range(3))
        if rpy not in config.RPY_AXES_OPTIONS:
            QMessageBox.warning(self, "Invalid angle axes",
                                "The roll / pitch / yaw axes are not a right-handed cyclic set.")
            return
        self._mapping = labels
        self._matrix = M
        self._rpy_axes = rpy
        self.accept()

    @property
    def rpy_axes(self):
        return self._rpy_axes

    @property
    def mapping(self):
        return self._mapping

    @property
    def matrix(self):
        return self._matrix


# ---------------------------------------------------------------------------
# Incremental adjustment table
# ---------------------------------------------------------------------------
class _AdjGridDelegate(QStyledItemDelegate):
    """Draws the table's cells and its grid itself, so the origin column shows
    no lines inside a group: every cell gets its right and bottom line except
    an origin cell that continues into the next row of the same group, and the
    group's name is drawn once, centred over the group's rows (in the paint
    of the group's last row, over the rows painted before it)."""

    def __init__(self, dialog):
        super().__init__(dialog)
        self._dlg = dialog
        self.groups = []                   # per row: (first_row, last_row)

    def paint(self, painter, option, index):
        t = self._dlg.table
        rect = option.rect
        painter.save()
        painter.fillRect(rect, t.palette().base())
        col, row = index.column(), index.row()
        pen = QPen(QColor("#8A8A8A"))
        pen.setWidth(1)
        painter.setPen(pen)
        first, last = self.groups[row] if row < len(self.groups) else (row, row)
        painter.drawLine(rect.right(), rect.top(), rect.right(), rect.bottom())
        if not (col == 0 and row < last):
            painter.drawLine(rect.left(), rect.bottom(), rect.right(), rect.bottom())
        item = t.item(row, col)
        if col == 0:
            if row == last:
                top = t.rowViewportPosition(first)
                span = rect.adjusted(0, top - rect.top(), 0, 0)
                painter.setPen(option.palette.color(QPalette.Text))
                painter.setFont(item.font() if item else option.font)
                painter.drawText(span, Qt.AlignHCenter | Qt.AlignVCenter, index.data() or "")
        elif item is not None and index.data():
            painter.setPen(option.palette.color(QPalette.Text))
            painter.setFont(item.font())
            painter.drawText(rect.adjusted(4, 0, -4, 0), int(item.textAlignment()), index.data())
            if item.font().weight() >= QFont.Weight.Black:
                # "double bold": the black weight plus a second pass one pixel over
                painter.drawText(rect.adjusted(5, 0, -3, 0), int(item.textAlignment()), index.data())
        painter.restore()


class IncrementalAdjDialog(QDialog):
    """Application-modal window (see adj_table.py for the maths).

    Top: one row per origin with a check box for each of X, Y, Z, Roll,
    Pitch, Yaw.  Then, right-justified, the decimal places.  Then the table,
    embedded without a frame and exactly as wide as its columns (widths from
    the content, not resizable): one row per ticked (origin, axis) in X, Y,
    Z, Roll, Pitch, Yaw order within each origin, origins in list order; the
    origin name once per group (centred over its rows, wrapped once after 7
    characters), the axis with a + sign, the six leg entries (= unit ratio x
    turn; every entry that reads +1 or -1 at the chosen decimals is bold) and
    the row's Turn [deg] box (positive or negative, one decimal, |turn| at
    most 99999.9, live).  "Round up above:" (0.99 by default, not saved) takes
    any unit ratio whose rounded magnitude exceeds the chosen threshold, but is
    below 1, to exactly 1; its last entry turns that off.  From Home / From
    New chooses the pose the whole table is computed at: the zero-displacement
    configuration, or the new absolute pose shown in the main window.  Bold marks the legs whose unit
    ratio reads +/-1, decided at turn = 1.0 and kept as the turns change (see
    adj_table.apply_turns).  To the right of the table, in line with each row,
    a square x button resets that row's turn to 1.0.  The table (with its reset
    column) is centred in the window with a margin of about four characters on
    each side; the window is as wide as the wider of that and the tick grid.

    Export writes text, Excel (live formulas, built-in writer) or PNG, always
    of the unit table (every turn 1.0), leaving the window's own turns alone.  Confirm keeps the
    set-up (ticks, turns, decimals) in the program (saved by Save
    Everything); Close discards the changes, like the other windows.
    `compute(selections) -> rows` and `context` come from the main window.
    """
    ROW_H = 26
    CELL_PAD = 14                          # pixels added to the text width of a column
    GAP_CHARS = 4                          # margin left and right of the table, in characters

    def __init__(self, parent, origins, active, compute, context, cfg, view=None):
        super().__init__(parent)
        self.setWindowTitle("Incremental Adjustment Table")
        self.setWindowModality(Qt.ApplicationModal)
        self.setModal(True)
        self._compute = compute
        self._ctx = context
        # The view settings (decimals, round-up threshold, pose choice) live for
        # as long as the program runs, so reopening the window finds them as
        # they were left, whether it was closed with Confirm or with Close.
        # They are not part of the saved set-up.
        view = dict(view or {})
        self._origins = origins
        self._rows = []
        self._turns = {}                      # row_key -> turn multiplier [deg]
        self._labels = {}                     # row_key -> the user's label for the row
        self._turn_edits = {}                 # row_key -> NumberLineEdit
        self._label_edits = {}                # row_key -> NameLineEdit
        self._reset_btns = []
        for i, r in enumerate(cfg["rows"]):
            for a, t in zip(adj_table.AXES, r["turns"]):
                if abs(t - adj_table.DEFAULT_TURN) > 0:
                    self._turns[(i, "+" + a)] = t
            for a, text in zip(adj_table.AXES, r.get("labels", [])):
                if text:
                    self._labels[(i, "+" + a)] = text
        never_confirmed = settings_io.adj_config_is_default(cfg)

        lay = QVBoxLayout(self)
        lay.setSpacing(8)
        lay.setSizeConstraint(QLayout.SetFixedSize)   # the window always fits its content exactly
        intro = QLabel(
            "Tick the axes to tabulate. Leg entry = unit ratio \u00d7 Turn [\u00b0]: the "
            "actuator turn of each leg for a small move in the + direction of the row's "
            "axis of that origin's frame " + adj_table.SIGN_NOTE + ".")
        intro.setWordWrap(True)
        lay.addWidget(intro)
        self._intro = intro

        # ---- selection grid: evenly spread columns ----
        # the tick grid (names + boxes) is one unit centred in the window
        grid = QGridLayout()
        grid.setHorizontalSpacing(0)
        grid.setVerticalSpacing(6)
        grid.setContentsMargins(0, 0, 0, 0)
        hdr = QLabel("Origin")
        f = hdr.font(); f.setBold(True); hdr.setFont(f)
        hdr.setAlignment(Qt.AlignHCenter | Qt.AlignVCenter)
        grid.addWidget(hdr, 0, 0)
        for c, ax in enumerate(adj_table.AXES):
            h = QLabel(ax)
            hf = h.font(); hf.setBold(True); h.setFont(hf)
            h.setAlignment(Qt.AlignHCenter | Qt.AlignVCenter)
            grid.addWidget(h, 0, c + 1)
        self._checks = []                     # [origin][axis] -> QCheckBox
        for i, o in enumerate(origins):
            lbl = QLabel(str(o["name"]))
            lbl.setAlignment(Qt.AlignHCenter | Qt.AlignVCenter)
            grid.addWidget(lbl, i + 1, 0)
            row = []
            for c, ax in enumerate(adj_table.AXES):
                cb = QCheckBox()
                if never_confirmed:
                    cb.setChecked(i == active - 1)   # first use: the active origin fully ticked
                else:
                    cb.setChecked(ax in cfg["rows"][i]["axes"])
                cb.toggled.connect(self.refresh)
                grid.addWidget(cb, i + 1, c + 1, Qt.AlignHCenter | Qt.AlignVCenter)
                row.append(cb)
            self._checks.append(row)
        grid.setColumnMinimumWidth(0, 150)       # names centred in it; the same gap follows it
        grid.setColumnMinimumWidth(1, 66 + 14)
        for c in range(2, 7):
            grid.setColumnMinimumWidth(c, 66)
        self._grid_w = 150 + (66 + 14) + 5 * 66
        # a fixed-width holder placed with one part of the free space on its left
        # and two parts on its right (stretch factors 1 : 2)
        grid_holder = QWidget()
        grid_holder.setLayout(grid)
        grid_holder.setFixedWidth(self._grid_w)
        grid_row = QHBoxLayout()
        grid_row.setContentsMargins(0, 0, 0, 0)
        grid_row.addStretch(1)
        grid_row.addWidget(grid_holder)
        grid_row.addStretch(2)
        lay.addLayout(grid_row)

        # ---- decimals, right-justified ----
        # the row above the table: "Decimal places" flush with the table's left
        # edge, "Round up above 0.99" (tick to the right of its label) flush
        # with the table's right edge; both spacers are set in refresh, so the
        # row follows the table as it changes width
        dec_row = QHBoxLayout()
        self._dec_left_spacer = QSpacerItem(0, 1, QSizePolicy.Fixed, QSizePolicy.Minimum)
        self._dec_right_spacer = QSpacerItem(0, 1, QSizePolicy.Fixed, QSizePolicy.Minimum)
        dec_row.addItem(self._dec_left_spacer)
        dec_lbl = QLabel("Decimal places:")
        self.decimals = QComboBox()
        for d in adj_table.DECIMALS_CHOICES:
            self.decimals.addItem(str(d))
        self.decimals.setCurrentText(str(view.get("decimals", cfg["decimals"])))
        self.decimals.setFixedWidth(64)
        self.decimals.currentIndexChanged.connect(self.refresh)
        dec_row.addWidget(dec_lbl)
        dec_row.addWidget(self.decimals)
        dec_row.addStretch(1)
        # which pose the table is computed from, evenly spaced across the row
        self.from_home = QRadioButton("From Home")
        self.from_new = QRadioButton("From New")
        self._pose_group = QButtonGroup(self)          # one or the other, never both
        for i, rb in enumerate((self.from_home, self.from_new)):
            rb.setLayoutDirection(Qt.RightToLeft)      # the button sits after its label
            self._pose_group.addButton(rb, i)
        self.from_home.setChecked(bool(view.get("from_home", True)))
        self.from_new.setChecked(not self.from_home.isChecked())
        self.from_home.setToolTip("Compute the table at the zero-displacement (home) configuration")
        self.from_new.setToolTip("Compute the table at the new absolute pose shown in the main window")
        self._pose_group.buttonToggled.connect(lambda *_: self.refresh())
        dec_row.addWidget(self.from_home)
        dec_row.addStretch(1)
        dec_row.addWidget(self.from_new)
        dec_row.addStretch(1)
        round_lbl = QLabel("Round up above:")
        self.round_up = QComboBox()
        for t in adj_table.ROUND_UP_CHOICES:
            self.round_up.addItem(adj_table.round_up_text(t))
        self.round_up.setCurrentText(
            adj_table.round_up_text(view.get("round_up", adj_table.DEFAULT_ROUND_UP)))
        self.round_up.setFixedWidth(72)
        tip = ("Show a unit ratio whose rounded magnitude is above this, but below 1, "
               "as exactly 1 (and mark that leg bold); '- off -' leaves the rounded values alone")
        round_lbl.setToolTip(tip)
        self.round_up.setToolTip(tip)
        self.round_up.currentIndexChanged.connect(self.refresh)
        dec_row.addWidget(round_lbl)
        dec_row.addWidget(self.round_up)
        dec_row.addItem(self._dec_right_spacer)
        self._dec_row = dec_row
        lay.addLayout(dec_row)

        # ---- table + reset column ----
        self.COLS = ["Origin", "Axis", "Label"] + list(adj_table.LEGS) + ["Turn [\u00b0]"]
        self.table = QTableWidget(0, len(self.COLS))
        t = self.table
        t.setHorizontalHeaderLabels(self.COLS)
        t.verticalHeader().setVisible(False)
        t.setEditTriggers(QTableWidget.NoEditTriggers)
        t.setSelectionMode(QTableWidget.NoSelection)
        t.setFocusPolicy(Qt.NoFocus)
        t.setShowGrid(False)                   # the delegate draws the grid
        t.setFrameShape(QFrame.NoFrame)
        self._delegate = _AdjGridDelegate(self)
        t.setItemDelegate(self._delegate)
        t.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        t.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        t.setAutoScroll(False)
        # a 1 px outer border completes the grid (Qt draws grid lines between
        # cells only, so without it the left and bottom edges have no line)
        t.setStyleSheet("QTableWidget{border:1px solid #8A8A8A; gridline-color:#8A8A8A;} "
                        "QHeaderView::section{border:1px solid #8A8A8A; padding:2px;}")
        hh = t.horizontalHeader()
        hf = hh.font(); hf.setBold(True); hh.setFont(hf)
        hh.setSectionResizeMode(QHeaderView.Fixed)
        hh.setStretchLastSection(False)
        hh.setSectionsClickable(False)
        hh.setHighlightSections(False)
        self.reset_col = QWidget()
        self.reset_col.setFixedWidth(self.ROW_H)
        # a thin row above the table marking the two columns the user fills in
        self._user_row = QWidget()
        self._user_row.setFixedHeight(15)
        self._user_marks = []
        for _ in range(2):
            m = QLabel("user input", self._user_row)
            mf = m.font(); mf.setPointSize(8); mf.setItalic(True); m.setFont(mf)
            m.setStyleSheet("color:#888888;")
            m.setAlignment(Qt.AlignHCenter | Qt.AlignBottom)
            self._user_marks.append(m)
        table_col = QVBoxLayout()              # the marks sit directly over the table
        table_col.setContentsMargins(0, 0, 0, 0)
        table_col.setSpacing(2)
        table_col.addWidget(self._user_row, 0, Qt.AlignLeft)
        table_col.addWidget(t, 0, Qt.AlignLeft)
        reset_col_wrap = QVBoxLayout()
        reset_col_wrap.setContentsMargins(0, 0, 0, 0)
        reset_col_wrap.setSpacing(2)
        self._reset_spacer = QSpacerItem(1, self._user_row.height(), QSizePolicy.Minimum,
                                         QSizePolicy.Fixed)
        reset_col_wrap.addItem(self._reset_spacer)
        reset_col_wrap.addWidget(self.reset_col, 0, Qt.AlignTop)
        table_row = QHBoxLayout()
        table_row.setSpacing(6)
        table_row.addStretch(1)                # centred whatever the window width
        table_row.addLayout(table_col)
        table_row.addLayout(reset_col_wrap)
        table_row.addStretch(1)
        # the marks and the table are one block, so the marks sit just above
        # the columns they belong to
        lay.addLayout(table_row)

        # export buttons left-aligned with the table's left edge (the spacer is
        # sized in refresh), Confirm / Close at the right; one spacing throughout
        btn_row = QHBoxLayout()
        self._btn_left_spacer = QSpacerItem(0, 1, QSizePolicy.Fixed, QSizePolicy.Minimum)
        btn_row.addItem(self._btn_left_spacer)
        self.export_png_btn = QPushButton("Export .PNG ...")
        self.export_txt_btn = QPushButton("Export .TXT ...")
        self.export_xlsx_btn = QPushButton("Export .XLSX ...")
        self.ok = QPushButton("Confirm")
        self.close_btn = QPushButton("Close")
        for b in (self.export_png_btn, self.export_txt_btn, self.export_xlsx_btn, self.ok, self.close_btn):
            b.setFixedHeight(28)
            b.setAutoDefault(False)
        self.ok.setDefault(False)      # Enter updates the table, it does not confirm
        for b in (self.export_png_btn, self.export_txt_btn, self.export_xlsx_btn):
            btn_row.addWidget(b)
        btn_row.addStretch(1)
        btn_row.addWidget(self.ok)
        btn_row.addWidget(self.close_btn)
        self._btn_row = btn_row
        lay.addLayout(btn_row)
        self.export_png_btn.clicked.connect(lambda: self.export(".png"))
        self.export_txt_btn.clicked.connect(lambda: self.export(".txt"))
        self.export_xlsx_btn.clicked.connect(lambda: self.export(".xlsx"))
        self.ok.clicked.connect(self.accept)
        self.close_btn.clicked.connect(self.reject)

        self.refresh()

    # ------------------------------------------------------------------
    def selections(self):
        sel = {}
        for i, row in enumerate(self._checks):
            chosen = {ax for ax, cb in zip(adj_table.AXES, row) if cb.isChecked()}
            if chosen:
                sel[i] = chosen
        return sel

    def labels(self):
        """The user's row labels, keyed by row_key (kept for the session)."""
        return dict(self._labels)

    def view_state(self):
        """Decimals, round-up threshold and pose choice, to be handed back the
        next time the window is opened.  Not saved to the settings file."""
        return dict(decimals=self._decimals(), round_up=self._round_up(),
                    from_home=self._from_home())

    def config(self):
        """The set-up to keep: ticks and turns per origin, decimals."""
        rows = []
        for i, row in enumerate(self._checks):
            rows.append(dict(
                axes={ax for ax, cb in zip(adj_table.AXES, row) if cb.isChecked()},
                turns=[self._turns.get((i, "+" + ax), adj_table.DEFAULT_TURN) for ax in adj_table.AXES],
                labels=[self._labels.get((i, "+" + ax), "") for ax in adj_table.AXES]))
        return dict(decimals=self._decimals(), rows=rows)

    def _decimals(self):
        try:
            return int(self.decimals.currentText())
        except ValueError:
            return adj_table.DEFAULT_DECIMALS

    def _on_turn_edited(self, key, edit):
        """Live recalculation of one row as its Turn box is typed."""
        from .widgets import parse_number
        v = parse_number(edit.text())
        if v is None:
            return                            # partial entry ("-", "1."): keep the last value
        c = adj_table.clamp_turn(v)
        if abs(c - v) > 0:                    # beyond the cap: show the capped value
            edit.setText(adj_table.format_value(c, adj_table.TURN_DECIMALS))
        self._turns[key] = c
        self._update_row_values()

    def _reset_turn(self, key):
        self._turns[key] = adj_table.DEFAULT_TURN
        e = self._turn_edits.get(key)
        if e is not None:
            e.setText(adj_table.format_value(adj_table.DEFAULT_TURN, adj_table.TURN_DECIMALS))
        self._update_row_values()

    def keyPressEvent(self, event):
        """Enter (or Return) refreshes the table, as one expects after typing in
        a cell; it never presses Confirm."""
        if event.key() in (Qt.Key_Return, Qt.Key_Enter):
            self.refresh()
            return
        super().keyPressEvent(event)

    def _round_up(self):
        """The selected round-up threshold (0 when the menu says Disable)."""
        return adj_table.round_up_value(self.round_up.currentText())

    def _from_home(self):
        return bool(self.from_home.isChecked())

    def _update_row_values(self):
        """Rewrite the six leg cells of every row from unit ratio x turn (the
        bold legs are fixed by apply_turns and do not change with the turns)."""
        dec = self._decimals()
        adj_table.apply_turns(self._rows, self._turns, dec, self._round_up(), self._labels)
        heavy = self._heavy_font()
        for k, r in enumerate(self._rows):
            for j, v in enumerate(r["values"]):
                it = self.table.item(k, 3 + j)
                if it is None:
                    continue
                it.setText(adj_table.format_value(v, dec))
                it.setFont(heavy if j in r["bold"] else QFont(self.table.font()))
        self.table.viewport().update()          # repaint whole, so group names stay intact

    def _heavy_font(self):
        """The 'double bold' font for entries that read +/-1: black weight."""
        f = QFont(self.table.font())
        f.setWeight(QFont.Weight.Black)
        return f

    def _column_widths(self, dec):
        """Column widths, plus padding, from the widest text each column can
        ever show: the header, the origin names and axis labels, and for the
        numeric columns the largest possible entry (the turn cap 99999.9, so
        a leg entry is at most -99999.9 followed by the chosen decimals).  The
        width therefore depends only on the names and the decimal places."""
        fm = QFontMetrics(self.table.font())
        hb = QFont(self.table.font()); hb.setBold(True)
        fmb = QFontMetrics(hb)
        widest_leg = "-" + adj_table.format_value(adj_table.TURN_MAX, dec)
        widest_turn = "-" + adj_table.format_value(adj_table.TURN_MAX, adj_table.TURN_DECIMALS)
        sizes = adj_table.group_sizes(self._rows)
        widths = []
        for c, name in enumerate(self.COLS):
            w = max(fmb.horizontalAdvance(line) for line in name.split("\n"))
            if c == 0:
                for r in self._rows:
                    for line in adj_table.display_name(r, sizes).split("\n"):
                        w = max(w, fm.horizontalAdvance(line))
            elif c == 1:
                w = max([w] + [fm.horizontalAdvance(r["axis"]) for r in self._rows])
            elif c == 2:
                w = max([w] + [fmb.horizontalAdvance(r.get("label") or "") for r in self._rows])
            elif c <= 8:
                w = max(w, fmb.horizontalAdvance(widest_leg))
            else:
                w = max(w, fm.horizontalAdvance(widest_turn))
            widths.append(w + self.CELL_PAD)
        return widths

    def refresh(self, *_):
        dec = self._decimals()
        self._rows = adj_table.apply_turns(self._compute(self.selections(), self._from_home()),
                                           self._turns, dec, self._round_up(), self._labels)
        t = self.table
        t.clearSpans()
        t.setRowCount(0)                       # drops the old cell widgets
        t.setRowCount(len(self._rows))
        self._turn_edits = {}
        self._label_edits = {}
        heavy = self._heavy_font()
        sizes = adj_table.group_sizes(self._rows)
        groups = []
        for k, r in enumerate(self._rows):
            first = k
            while first > 0 and self._rows[first - 1]["origin"] == r["origin"]:
                first -= 1
            last = k
            while last + 1 < len(self._rows) and self._rows[last + 1]["origin"] == r["origin"]:
                last += 1
            groups.append((first, last))
        self._delegate.groups = groups
        for k, r in enumerate(self._rows):
            t.setRowHeight(k, self.ROW_H)
            key = adj_table.row_key(r)
            # every row of a group carries the name; the delegate draws it once,
            # centred over the group (wrapped only when the group has several rows)
            item = QTableWidgetItem(adj_table.display_name(r, sizes))
            item.setTextAlignment(Qt.AlignHCenter | Qt.AlignVCenter)
            t.setItem(k, 0, item)
            ax = QTableWidgetItem(r["axis"])
            ax.setTextAlignment(Qt.AlignHCenter | Qt.AlignVCenter)
            t.setItem(k, 1, ax)
            # the row's own label: free text, centred, up to adj_table.LABEL_MAX
            lab = NameLineEdit(r["label"], max_len=adj_table.LABEL_MAX, forbidden='"')
            lab.setAlignment(Qt.AlignHCenter | Qt.AlignVCenter)
            lab.setFrame(False)
            lab_font = QFont(t.font()); lab_font.setBold(True)
            lab.setFont(lab_font)                                # bold, dark red
            lab.setStyleSheet(f"color:{adj_table.LABEL_COLOR};")
            lab.textChanged.connect(lambda text, kk=key: self._labels.__setitem__(kk, text))
            lab.editingFinished.connect(self.refresh)      # the column refits when you leave it
            self._label_edits[key] = lab
            holder_l = QWidget()
            holder_l.setAttribute(Qt.WA_TranslucentBackground, True)
            hl_l = QHBoxLayout(holder_l)
            hl_l.setContentsMargins(0, 0, 1, 1)
            hl_l.setSpacing(0)
            hl_l.addWidget(lab)
            t.setCellWidget(k, 2, holder_l)
            for j, v in enumerate(r["values"]):
                it = QTableWidgetItem(adj_table.format_value(v, dec))
                it.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
                if j in r["bold"]:
                    it.setFont(heavy)
                t.setItem(k, 3 + j, it)
            edit = NumberLineEdit(adj_table.format_value(r["turn"], adj_table.TURN_DECIMALS),
                                  decimals=adj_table.TURN_DECIMALS)
            edit.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
            edit.setFrame(False)
            edit.textChanged.connect(lambda _t, kk=key, ee=edit: self._on_turn_edited(kk, ee))
            self._turn_edits[key] = edit
            # the box sits in a transparent holder one pixel short of the
            # cell's right and bottom edges, so the grid lines drawn there by
            # the delegate stay visible
            holder = QWidget()
            holder.setAttribute(Qt.WA_TranslucentBackground, True)
            hl = QHBoxLayout(holder)
            hl.setContentsMargins(0, 0, 1, 1)
            hl.setSpacing(0)
            hl.addWidget(edit)
            t.setCellWidget(k, 9, holder)
        # exact size: columns from the content, all rows shown (no scrolling)
        widths = self._column_widths(dec)
        for c, w in enumerate(widths):
            t.setColumnWidth(c, w)
        header_h = t.horizontalHeader().sizeHint().height()
        t.horizontalHeader().setFixedHeight(header_h)
        # the widget is the content plus its 1 px border on each side: if the
        # viewport were even a pixel smaller than the columns, focusing a Turn
        # box would scroll the view by that pixel and the table would appear
        # to shift
        fw = max(t.frameWidth(), 1)
        table_w = sum(widths) + 2 * fw
        table_h = header_h + max(len(self._rows), 1) * self.ROW_H + 2 * fw
        t.setFixedSize(table_w, table_h)
        t.horizontalScrollBar().setValue(0)
        t.verticalScrollBar().setValue(0)

        # the "user input" marks sit over the Label and the Turn columns; the
        # marks widget shares the table's left edge, so a centre is just the
        # column's own centre plus the table's border
        self._user_row.setFixedWidth(table_w)
        centres = [fw + sum(widths[:c]) + 0.5 * widths[c] for c in (2, len(widths) - 1)]
        for m, cx in zip(self._user_marks, centres):
            mw = m.sizeHint().width()
            m.setGeometry(int(cx - 0.5 * mw), 0, mw, self._user_row.height())
            m.show()

        # reset buttons, one per row, in line with the rows: square, the row
        # height less 2 px, the x glyph centred in the button
        for b in self._reset_btns:
            b.setParent(None)
            b.deleteLater()
        self._reset_btns = []
        side = self.ROW_H - 2
        self.reset_col.setFixedSize(side, t.height())
        bf = QFont(self.font()); bf.setPointSize(bf.pointSize() + 2)
        for k, r in enumerate(self._rows):
            key = adj_table.row_key(r)
            btn = QPushButton("\u00d7", self.reset_col)
            btn.setFont(bf)
            btn.setStyleSheet("QPushButton{padding:0px; margin:0px; text-align:center;}")
            btn.setGeometry(0, fw + header_h + k * self.ROW_H + 1, side, side)
            btn.setToolTip("Reset this row's turn to 1.0")
            btn.setAutoDefault(False)
            btn.clicked.connect(lambda _c=False, kk=key: self._reset_turn(kk))
            btn.show()
            self._reset_btns.append(btn)

        # window width: the tick grid, or the table plus its reset column with a
        # four-character margin on each side, whichever is wider; the table row
        # is centred in either case (see the stretches around it)
        gap = self.GAP_CHARS * QFontMetrics(self.font()).averageCharWidth()
        block_w = table_w + 6 + side           # table plus its reset column
        content_w = max(self._grid_w + 2 * gap, block_w + 2 * gap)
        self._intro.setFixedWidth(content_w)
        self._intro.setFixedHeight(max(int(self._intro.heightForWidth(content_w)), 1))
        # the export buttons start where the table starts (it is centred in
        # content_w), and the decimals row spans the table's own left and right
        # edges
        left = int(round((content_w - block_w) / 2))
        self._btn_left_spacer.changeSize(max(left - self._btn_row.spacing(), 0), 1,
                                         QSizePolicy.Fixed, QSizePolicy.Minimum)
        self._btn_row.invalidate()
        right_gap = max(content_w - (left + table_w), 0)
        self._dec_left_spacer.changeSize(max(left - self._dec_row.spacing(), 0), 1,
                                         QSizePolicy.Fixed, QSizePolicy.Minimum)
        self._dec_right_spacer.changeSize(max(right_gap - self._dec_row.spacing(), 0), 1,
                                          QSizePolicy.Fixed, QSizePolicy.Minimum)
        self._dec_row.invalidate()
        self.layout().activate()               # the SetFixedSize constraint resizes the window

    _EXPORT_FILTERS = {".png": "PNG image (*.png)", ".txt": "Text file (*.txt)",
                       ".xlsx": "Excel workbook (*.xlsx)"}

    def export(self, ext):
        """Export the table as `ext` (.png, .txt or .xlsx): one save dialog
        limited to that type, starting in the last folder used anywhere in
        the program (savedir)."""
        if not self._rows:
            QMessageBox.information(self, "Nothing to export", "Tick at least one axis first.")
            return
        ext = ext.lower()
        path, _ = QFileDialog.getSaveFileName(
            self, f"Export incremental adjustment table as {ext[1:].upper()}",
            savedir.start_path("incremental_adjustment_table" + ext), self._EXPORT_FILTERS[ext])
        if not path:
            return
        if os.path.splitext(path)[1].lower() != ext:
            path += ext
        savedir.remember(path)
        dec = self._decimals()
        c = self._ctx
        # An export is always of the unit table: every turn 1.0, so the file
        # shows the ratios themselves.  The turns typed in the window are left
        # exactly as they are.
        rows = adj_table.apply_turns(self._compute(self.selections(), self._from_home()), {}, dec,
                                     self._round_up(), self._labels)
        source = c["source"](self._from_home()) if callable(c.get("source")) else ""
        try:
            if ext == ".txt":
                with open(path, "w", encoding="utf-8") as f:
                    f.write(adj_table.to_text(rows, dec, c["calc_name"], c["frame_name"],
                                              c["rpy_axes"], source))
            else:
                # previews of the first (at most two) origins in the table, each
                # in its own frame at the default view, labelled with its name
                sketches = []
                if callable(c.get("sketch")):
                    seen = []
                    for r in rows:
                        if r["origin"] not in seen:
                            seen.append(r["origin"])
                    for oi in seen[:adj_table.MAX_SKETCHES]:
                        try:
                            name = self._origins[oi]["name"]
                            w_in, h_in = adj_table.sketch_size_in(len(seen[:adj_table.MAX_SKETCHES]))
                            sketches.append((name, c["sketch"](oi, w_in, h_in)))
                        except Exception as exc:
                            print(f"origin preview could not be rendered ({exc!r}); exporting without it")
                if ext == ".xlsx":
                    adj_table.to_xlsx(path, rows, dec, c["calc_name"], c["frame_name"], c["rpy_axes"],
                                      sketches=sketches, source=source)
                else:
                    adj_table.to_png(path, rows, dec, c["calc_name"], c["frame_name"], c["rpy_axes"],
                                     sketches=sketches, source=source)
        except Exception as exc:
            QMessageBox.critical(self, "Export failed", f"{exc}")
            print(f"incremental adjustment table export failed: {exc}")
            return
        print(f"incremental adjustment table exported to {path}")


# ---------------------------------------------------------------------------
# Quit dialog
# ---------------------------------------------------------------------------
def quit_dialog(parent=None):
    """Return 'save', 'nosave', or 'cancel'."""
    box = QMessageBox(parent)
    box.setWindowTitle("Quit")
    box.setText("Do you want to save your configuration before quitting?")
    save_btn = box.addButton("Quit with saving", QMessageBox.AcceptRole)
    nosave_btn = box.addButton("Quit without saving", QMessageBox.DestructiveRole)
    cancel_btn = box.addButton("Cancel", QMessageBox.RejectRole)
    box.setDefaultButton(save_btn)
    box.exec()
    clicked = box.clickedButton()
    if clicked is save_btn:
        return "save"
    if clicked is nosave_btn:
        return "nosave"
    return "cancel"
