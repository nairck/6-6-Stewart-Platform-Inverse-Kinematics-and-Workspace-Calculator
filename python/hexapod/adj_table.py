"""
Incremental adjustment table.

For every selected (origin, axis) pair the table gives the ratio of actuator
rotation each leg needs for a small move of the platform in the + direction
of that axis of that origin's frame, normalized so that the leg turning the
most has magnitude 1.  A manual adjustment can then be made by turning the
reference leg by any amount and every other leg by that amount times its
entry (sign included: a negative entry turns the other way).

Maths (all in the frame the values are currently displayed in, frame A):

  * platform pose (R, t) from the displayed roll, pitch, yaw, X, Y, Z with the
    current rpy-axes assignment; base joints a_j, platform joints b_j;
    leg lengths L_j(R, t) = |a_j - (R b_j + t)|;
  * origin o has rotation R_o and offset d_o relative to Origin 1 (see
    kinematics.origin_frame); in frame A its point is c = R_A^T (d_o - d_A)
    and its axis a is n = R_A^T R_o e_a (e_a = X, Y, Z, or the axis roll,
    pitch, yaw rotate about);
  * a translation move: t' = t +/- delta n;
  * a rotation move about the origin's point and axis: Rot = Rodrigues(n,
    +/- delta), R' = Rot R, t' = Rot (t - c) + c;
  * dL_j = (L_j(+delta) - L_j(-delta)) / 2 (central difference: the ratios
    are independent of delta to second order), actuator rotation
    dtheta_j = dL_j * 360 / lead, ratio_j = dtheta_j / max_k |dtheta_k|.

Row order: origins in list order, and within an origin the checked axes in
the fixed order X, Y, Z, Roll, Pitch, Yaw.

Each row also carries a turn multiplier [deg] (default 1.0, one decimal):
the manual turn given to the reference leg(s).  The displayed and exported
leg entries are ratio * turn, i.e. the degrees of turn every leg needs for
that move; with turn = 1.0 they are the unit ratios themselves.
"""
from __future__ import annotations
import datetime as _dt
import numpy as np
from . import kinematics as K
from . import config

LEG_COLORS = tuple(config.LEG_COLORS)
MAX_SKETCHES = 2            # origin previews shown in the exports (at most)
SKETCH_H_IN = 1.3           # height of each preview drawing [in]
SKETCH_LABEL_IN = 0.2       # room for the origin name above each preview [in]
LEGEND_W_IN = 0.7           # width reserved for the leg legend [in]
TABLE_COL_W = [1.45, 0.75] + [0.85] * 6 + [0.9]      # PNG column widths [in]


def sketch_size_in(count):
    """(width, height) in inches of each preview when `count` are shown side by
    side in the right half of the top section."""
    right_half = 0.5 * sum(TABLE_COL_W) - LEGEND_W_IN
    gap = 0.15
    w = (right_half - gap * (count + 1)) / max(count, 1)
    return min(w, SKETCH_H_IN * 1.7), SKETCH_H_IN

AXES = ("X", "Y", "Z", "Roll", "Pitch", "Yaw")
LEGS = tuple(f"Leg {j}" for j in range(1, 7))
DELTA_MM = 0.1            # translation perturbation [mm]
DELTA_DEG = 0.01          # rotation perturbation [deg]
DECIMALS_CHOICES = (0, 1, 2, 3, 4, 5, 6)
DEFAULT_DECIMALS = 3


def _rodrigues(n, angle_deg):
    n = np.asarray(n, float)
    n = n / (np.linalg.norm(n) or 1.0)
    th = np.radians(angle_deg)
    Kx = np.array([[0, -n[2], n[1]], [n[2], 0, -n[0]], [-n[1], n[0], 0]])
    return np.eye(3) + np.sin(th) * Kx + (1 - np.cos(th)) * (Kx @ Kx)


def leg_lengths(a, b, R, t):
    """|a_j - (R b_j + t)| for the six legs."""
    return np.linalg.norm(np.asarray(a, float) - ((R @ np.asarray(b, float).T).T + t), axis=1)


def wrap_name(name, width=7):
    """Wrap an origin name once for the table's first column: only when it is
    longer than `width` and has a space to break at; the break is the last
    space that keeps the first line within `width`, or the first space if
    none does.  A single word is never broken."""
    name = str(name)
    if len(name) <= width or " " not in name:
        return name
    spaces = [i for i, ch in enumerate(name) if ch == " "]
    fitting = [i for i in spaces if i <= width]
    s = fitting[-1] if fitting else spaces[0]
    return name[:s].rstrip() + "\n" + name[s + 1:].lstrip()


def group_sizes(rows):
    """{origin index: number of rows} for the rows of a table."""
    sizes = {}
    for r in rows:
        sizes[r["origin"]] = sizes.get(r["origin"], 0) + 1
    return sizes


def display_name(row, sizes):
    """The origin name as shown in the table's first column: wrapped once
    after 7 characters when the origin has several rows, on one line when it
    has a single row (the column is widened to fit instead)."""
    return wrap_name(row["name"]) if sizes.get(row["origin"], 1) > 1 else row["name"]


def compute_rows(geom, pose, origins, active, rpy_axes, selections, lead):
    """Build the table rows.

    geom       : dict with xsi, ysi, zsi, xmi, ymi, zmi (displayed, frame A)
    pose       : (roll, pitch, yaw, px, py, pz) displayed (frame A)
    origins    : the origin list (frames relative to Origin 1)
    active     : 1-based index of the frame the values are displayed in
    rpy_axes   : 'XYZ', 'YZX' or 'ZXY'
    selections : {origin_index (0-based): set of axis names}
    lead       : actuator lead [mm/rev]

    Returns a list of dicts: origin (0-based), name, axis ('+X', ...),
    ratios (6), dtheta (6, deg per delta move), ref (0-based leg with the largest
    turn), ones (tuple of 0-based legs whose |ratio| is 1, i.e. ref and any tie).
    """
    a = np.column_stack([geom["xsi"], geom["ysi"], geom["zsi"]]).astype(float)
    b = np.column_stack([geom["xmi"], geom["ymi"], geom["zmi"]]).astype(float)
    roll, pitch, yaw, px, py, pz = [float(v) for v in pose]
    R = K._rotation(roll, pitch, yaw, rpy_axes)
    t = np.array([px, py, pz], float)
    R_A, d_A = K.origin_frame(origins[active - 1], rpy_axes)
    lead = float(lead) if lead else 1.0
    rows = []
    for oi, o in enumerate(origins):
        chosen = selections.get(oi, set())
        if not chosen:
            continue
        R_o, d_o = K.origin_frame(o, rpy_axes)
        c = R_A.T @ (d_o - d_A)
        for ai, axis in enumerate(AXES):
            if axis not in chosen:
                continue
            if ai < 3:
                e = np.eye(3)[ai]
            else:
                e = np.eye(3)["XYZ".index(rpy_axes[ai - 3])]
            n = R_A.T @ R_o @ e
            if ai < 3:
                Lp = leg_lengths(a, b, R, t + DELTA_MM * n)
                Lm = leg_lengths(a, b, R, t - DELTA_MM * n)
            else:
                Rp, Rm = _rodrigues(n, DELTA_DEG), _rodrigues(n, -DELTA_DEG)
                Lp = leg_lengths(a, b, Rp @ R, Rp @ (t - c) + c)
                Lm = leg_lengths(a, b, Rm @ R, Rm @ (t - c) + c)
            dL = 0.5 * (Lp - Lm)
            dtheta = dL * 360.0 / lead
            mag = np.abs(dtheta)
            ref = int(np.argmax(mag))
            if mag[ref] > 0:
                ratios = dtheta / mag[ref]
            else:
                ratios = np.zeros(6)
            ones = tuple(int(j) for j in range(6) if abs(abs(ratios[j]) - 1.0) < 1e-9)
            rows.append(dict(origin=oi, name=str(o["name"]), axis="+" + axis,
                             ratios=ratios, dtheta=dtheta, ref=ref, ones=ones))
    return rows


def format_value(v, decimals):
    return f"{float(v):.{int(decimals)}f}"


def is_unit(v, decimals):
    """True when the entry reads +1 or -1 at the chosen decimals (bold rule)."""
    return abs(abs(round(float(v), int(decimals))) - 1.0) < 1e-12


DEFAULT_TURN = 1.0
TURN_DECIMALS = 1
ROUND_UP_THRESHOLD = 0.99      # "Round up above 0.99": |unit ratio| > this reads as 1
DEFAULT_ROUND_UP = True
TURN_MAX = 99999.9        # |turn| is capped here, so the table width is bounded


def clamp_turn(v):
    v = round(float(v), TURN_DECIMALS)
    return max(-TURN_MAX, min(TURN_MAX, v))


def row_key(row):
    return (row["origin"], row["axis"])


def unit_ratios(row, decimals, round_up=DEFAULT_ROUND_UP):
    """The row's unit ratios as the table reads them: rounded to `decimals`
    and, when `round_up` is set, any magnitude above ROUND_UP_THRESHOLD (but
    not yet 1) taken to exactly +/-1, so 0.997 at three decimals reads 1.000."""
    v = np.round(np.asarray(row["ratios"], float), int(decimals))
    if round_up:
        snap = (np.abs(v) > ROUND_UP_THRESHOLD) & (np.abs(v) < 1.0)
        v = np.where(snap, np.sign(v), v)
    return v


def apply_turns(rows, turns, decimals=DEFAULT_DECIMALS, round_up=DEFAULT_ROUND_UP):
    """Attach to every row the turn multiplier (from `turns`, keyed by
    row_key, default DEFAULT_TURN), the unit ratios as the table reads them
    (`unit`, see unit_ratios), the leg entries values = unit * turn, and the
    legs shown in bold.

    Bold is decided from the UNIT state (turn = 1.0): the legs whose unit ratio
    reads +/-1 at the chosen decimals.  Those legs stay bold whatever turns are
    entered afterwards, so the reference legs of each move remain visible; the
    set is recomputed only when the decimals or the round-up option change,
    since both change what "reads 1" means.  Returns the rows.
    """
    for r in rows:
        m = float(turns.get(row_key(r), DEFAULT_TURN))
        r["turn"] = clamp_turn(m)
        unit = unit_ratios(r, decimals, round_up)
        r["unit"] = unit
        r["values"] = unit * r["turn"]
        r["bold"] = tuple(int(j) for j in range(6) if is_unit(unit[j], decimals))
    return rows


def _bold(row, j, value, decimals):
    """Whether leg j of `row` is shown in bold: the legs fixed by apply_turns,
    or (for rows that never went through it) the entry reading +/-1."""
    if "bold" in row:
        return j in row["bold"]
    return is_unit(value, decimals)


def _values(row):
    return row["values"] if "values" in row else np.asarray(row["ratios"], float)


def _turn(row):
    return row.get("turn", DEFAULT_TURN)


SIGN_NOTE = "(sign gives the direction of turn: positive extends the leg, negative retracts it)"


def header_lines(calc_name, frame_name, rpy_axes, decimals):
    """The lines above the table in every export: title, provenance, and the
    one-sentence definition of a leg entry.  calc_name and decimals are
    accepted for the call signature but not shown."""
    now = _dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    return [
        "Incremental Adjustment Table",
        f"Generated {now}; frame '{frame_name}'; roll/pitch/yaw about {rpy_axes[0]}, {rpy_axes[1]}, {rpy_axes[2]}",
        "Leg entry = unit ratio x Turn [deg]: the actuator turn of each leg for a small move in the + direction "
        "of the row's axis of that origin's frame " + SIGN_NOTE + ".",
    ]


def to_text(rows, decimals, calc_name, frame_name, rpy_axes):
    """Plain-text table with box lines, origin names once per group."""
    head = header_lines(calc_name, frame_name, rpy_axes, decimals)
    cols = ["Origin", "Axis"] + list(LEGS) + ["Turn [deg]"]
    body = []
    for r in rows:
        body.append([r["name"], r["axis"]] + [format_value(v, decimals) for v in _values(r)]
                    + [format_value(_turn(r), TURN_DECIMALS)])
    widths = [len(c) for c in cols]
    for line in body:
        for i, cell in enumerate(line):
            widths[i] = max(widths[i], len(cell))
    sep = "+" + "+".join("-" * (w + 2) for w in widths) + "+"

    def fmt_line(cells, align):
        out = []
        for cell, w, al in zip(cells, widths, align):
            out.append(" " + (cell.ljust(w) if al == "l" else cell.rjust(w)) + " ")
        return "|" + "|".join(out) + "|"
    align = ["l", "l"] + ["r"] * 7
    lines = list(head) + ["", sep, fmt_line(cols, ["l"] * 9), sep]
    prev_origin = None
    for r, line in zip(rows, body):
        if prev_origin is not None and r["origin"] != prev_origin:
            lines.append(sep)
        cells = list(line)
        if r["origin"] == prev_origin:
            cells[0] = ""
        lines.append(fmt_line(cells, align))
        prev_origin = r["origin"]
    lines.append(sep)
    return "\n".join(lines) + "\n"


def _xml(text):
    return (str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


def _col_letter(c):
    """1-based column index -> Excel letters."""
    out = ""
    while c > 0:
        c, rem = divmod(c - 1, 26)
        out = chr(ord("A") + rem) + out
    return out


class _Xlsx:
    """A minimal, dependency-free .xlsx writer: one sheet, inline strings,
    numbers, formulas, merged cells, column widths and a fixed style set
    (fonts, thin borders, alignments, number formats).  Written with
    zipfile, so it works identically on every platform and build."""

    # style indices (cellXfs order below); the leg header / legend styles
    # follow, one per leg colour
    S_DEFAULT, S_TITLE, S_ITALIC, S_HEADER, S_TEXT_C, S_NUM, S_NUM_B, S_TURN, S_UNIT, S_UNIT_B = range(10)
    S_LEG_HDR = 10          # + j: bold, coloured, bordered, centred
    S_LEGEND = 16           # + j: bold, coloured, no border
    S_TITLE_WRAP, S_WRAP, S_LABEL = 22, 23, 24

    def __init__(self, decimals):
        self.rows = {}          # row -> {col: (kind, value, style)}
        self.merges = []
        self.widths = {}
        self.decimals = int(decimals)
        self.images = []        # (png_bytes, col, row, col_off_in, width_in, height_in)
        self.row_heights = {}   # row -> points

    def add_image(self, png_bytes, col, row, width_in, height_in, col_off_in=0.0):
        """A picture anchored at (col, row), 1-based, offset col_off_in inches
        into that column."""
        self.images.append((png_bytes, col, row, col_off_in, width_in, height_in))

    def row_height(self, row, points):
        self.row_heights[row] = points

    def cell(self, r, c, value, style=S_DEFAULT, kind="auto"):
        if kind == "auto":
            kind = "n" if isinstance(value, (int, float)) and not isinstance(value, bool) else "s"
        self.rows.setdefault(r, {})[c] = (kind, value, style)

    def formula(self, r, c, expr, style):
        self.rows.setdefault(r, {})[c] = ("f", expr, style)

    def merge(self, r1, c1, r2, c2):
        self.merges.append(f"{_col_letter(c1)}{r1}:{_col_letter(c2)}{r2}")

    def width(self, c, w):
        self.widths[c] = w

    def _styles_xml(self):
        dec_fmt = "0" if self.decimals == 0 else "0." + "0" * self.decimals
        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<numFmts count="3">'
            f'<numFmt numFmtId="164" formatCode="{_xml(dec_fmt)}"/>'
            '<numFmt numFmtId="165" formatCode="0.0"/>'
            '<numFmt numFmtId="166" formatCode="0.000000"/>'
            '</numFmts>'
            '<fonts count="11">'
            '<font><sz val="11"/><name val="Calibri"/></font>'
            '<font><b/><sz val="11"/><name val="Calibri"/></font>'
            '<font><b/><sz val="13"/><name val="Calibri"/></font>'
            '<font><i/><sz val="11"/><name val="Calibri"/></font>'
            '<font><sz val="11"/><color rgb="FF1F4E79"/><name val="Calibri"/></font>'
            + "".join(f'<font><b/><sz val="11"/><color rgb="FF{c[1:].upper()}"/><name val="Calibri"/></font>'
                      for c in LEG_COLORS) +
            '</fonts>'
            '<fills count="2"><fill><patternFill patternType="none"/></fill>'
            '<fill><patternFill patternType="gray125"/></fill></fills>'
            '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
            '<border><left style="thin"><color auto="1"/></left><right style="thin"><color auto="1"/></right>'
            '<top style="thin"><color auto="1"/></top><bottom style="thin"><color auto="1"/></bottom><diagonal/></border>'
            '</borders>'
            '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
            '<cellXfs count="25">'
            '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'                                   # default
            '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'                     # title
            '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'                     # italic
            '<xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1">'
            '<alignment horizontal="center" vertical="center"/></xf>'                                          # header
            '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">'
            '<alignment horizontal="center" vertical="center" wrapText="1"/></xf>'                             # centred text
            '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1">'
            '<alignment horizontal="right" vertical="center"/></xf>'                                           # number
            '<xf numFmtId="164" fontId="1" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1">'
            '<alignment horizontal="right" vertical="center"/></xf>'                                           # number bold
            '<xf numFmtId="165" fontId="4" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1">'
            '<alignment horizontal="right" vertical="center"/></xf>'                                           # turn
            '<xf numFmtId="166" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1">'
            '<alignment horizontal="right" vertical="center"/></xf>'                                           # unit ratio
            '<xf numFmtId="166" fontId="1" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1">'
            '<alignment horizontal="right" vertical="center"/></xf>'                                           # unit ratio bold
            + "".join(f'<xf numFmtId="0" fontId="{5 + j}" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1">'
                      '<alignment horizontal="center" vertical="center"/></xf>' for j in range(6))
            + "".join(f'<xf numFmtId="0" fontId="{5 + j}" fillId="0" borderId="0" xfId="0" applyFont="1"/>' for j in range(6)) +
            '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
            '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
            '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="bottom"/></xf>'
            '</cellXfs>'
            '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
            '</styleSheet>'
        )

    def _sheet_xml(self):
        parts = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                 '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">']
        if self.widths:
            parts.append("<cols>")
            for c in sorted(self.widths):
                parts.append(f'<col min="{c}" max="{c}" width="{self.widths[c]}" customWidth="1"/>')
            parts.append("</cols>")
        parts.append("<sheetData>")
        for r in sorted(set(self.rows) | set(self.row_heights)):
            ht = self.row_heights.get(r)
            parts.append(f'<row r="{r}" ht="{ht}" customHeight="1">' if ht else f'<row r="{r}">')
            if r not in self.rows:
                parts.append("</row>")
                continue
            for c in sorted(self.rows[r]):
                kind, value, style = self.rows[r][c]
                ref = f"{_col_letter(c)}{r}"
                if kind == "n":
                    parts.append(f'<c r="{ref}" s="{style}"><v>{float(value)!r}</v></c>')
                elif kind == "f":
                    parts.append(f'<c r="{ref}" s="{style}"><f>{_xml(value)}</f></c>')
                elif value is None or value == "":
                    parts.append(f'<c r="{ref}" s="{style}"/>')
                else:
                    parts.append(f'<c r="{ref}" s="{style}" t="inlineStr"><is><t xml:space="preserve">'
                                 f'{_xml(value)}</t></is></c>')
            parts.append("</row>")
        parts.append("</sheetData>")
        if self.merges:
            parts.append(f'<mergeCells count="{len(self.merges)}">')
            parts += [f'<mergeCell ref="{m}"/>' for m in self.merges]
            parts.append("</mergeCells>")
        if self.images:
            parts.append('<drawing xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rIdImg1"/>')
        parts.append("</worksheet>")
        return "".join(parts)

    # cell geometry (Calibri 11 defaults): column width in characters ->
    # pixels, row height in points -> pixels; 9525 EMU per pixel
    def _col_px(self, c):
        return int(self.widths.get(c, 8.43) * 7 + 5)

    def _row_px(self, r):
        return int(round(self.row_heights.get(r, 15.0) * 96.0 / 72.0))

    def _anchor_to(self, col, row, off_in, w_in, h_in):
        """(col, colOff, row, rowOff) of the far corner of a picture, from its
        near-corner cell and offset and its size in inches."""
        px = 96.0
        x = off_in * px + w_in * px
        c = col
        while x >= self._col_px(c):
            x -= self._col_px(c)
            c += 1
        y = h_in * px
        r = row
        while y >= self._row_px(r):
            y -= self._row_px(r)
            r += 1
        return c, int(x * 9525), r, int(y * 9525)

    def _drawing_xml(self):
        emu = 914400
        anchors = []
        for k, (_, col, row, off_in, w_in, h_in) in enumerate(self.images, start=1):
            c2, xoff2, r2, yoff2 = self._anchor_to(col, row, off_in, w_in, h_in)
            anchors.append(
                '<xdr:twoCellAnchor editAs="oneCell">'
                f'<xdr:from><xdr:col>{col - 1}</xdr:col><xdr:colOff>{int(off_in * 96 * 9525)}</xdr:colOff>'
                f'<xdr:row>{row - 1}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
                f'<xdr:to><xdr:col>{c2 - 1}</xdr:col><xdr:colOff>{xoff2}</xdr:colOff>'
                f'<xdr:row>{r2 - 1}</xdr:row><xdr:rowOff>{yoff2}</xdr:rowOff></xdr:to>'
                f'<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="{k + 1}" name="Preview {k}"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>'
                f'<xdr:blipFill><a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="rId{k}"/>'
                '<a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
                f'<xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{int(w_in * emu)}" cy="{int(h_in * emu)}"/></a:xfrm>'
                '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>'
                '<xdr:clientData/></xdr:twoCellAnchor>')
        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
            'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            + "".join(anchors) + '</xdr:wsDr>')

    def save(self, path, sheet_name="Incremental Adj", hidden=None, hidden_name="Unit ratios"):
        """Write the workbook.  `hidden` is an optional second _Xlsx whose sheet
        is stored hidden (used for the unit ratios the visible formulas refer
        to)."""
        import zipfile
        overrides = ['<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>']
        defaults = ''
        if self.images:
            overrides.append('<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>')
            defaults = '<Default Extension="png" ContentType="image/png"/>'
        sheets = [f'<sheet name="{_xml(sheet_name)}" sheetId="1" r:id="rId1"/>']
        wb_rel = ['<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>']
        if hidden is not None:
            overrides.append('<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>')
            sheets.append(f'<sheet name="{_xml(hidden_name)}" sheetId="2" state="hidden" r:id="rId3"/>')
            wb_rel.append('<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>')
        content_types = (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            + defaults +
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            + "".join(overrides) +
            '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
            '</Types>')
        rels = (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            '</Relationships>')
        workbook = (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets>' + "".join(sheets) + '</sheets>'
            '<calcPr fullCalcOnLoad="1"/>'
            '</workbook>')
        wb_rels = (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            + "".join(wb_rel) +
            '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
            '</Relationships>')
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", content_types)
            z.writestr("_rels/.rels", rels)
            z.writestr("xl/workbook.xml", workbook)
            z.writestr("xl/_rels/workbook.xml.rels", wb_rels)
            z.writestr("xl/styles.xml", self._styles_xml())
            z.writestr("xl/worksheets/sheet1.xml", self._sheet_xml())
            if hidden is not None:
                z.writestr("xl/worksheets/sheet2.xml", hidden._sheet_xml())
            if self.images:
                z.writestr("xl/worksheets/_rels/sheet1.xml.rels",
                           '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                           '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                           '<Relationship Id="rIdImg1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>'
                           '</Relationships>')
                z.writestr("xl/drawings/drawing1.xml", self._drawing_xml())
                rels = "".join(
                    f'<Relationship Id="rId{k}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image{k}.png"/>'
                    for k in range(1, len(self.images) + 1))
                z.writestr("xl/drawings/_rels/drawing1.xml.rels",
                           '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                           '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                           + rels + '</Relationships>')
                for k, img in enumerate(self.images, start=1):
                    z.writestr(f"xl/media/image{k}.png", img[0])


def to_xlsx(path, rows, decimals, calc_name, frame_name, rpy_axes, sketches=()):
    """Excel workbook: one visible sheet laid out like the PNG.  Top section:
    the title and definition in merged, wrapped cells over columns A..E (row
    heights set for the wrapped lines), up to MAX_SKETCHES origin previews on
    the right (columns F..H, each with its name above) and the bold,
    leg-coloured legend in the Turn column.  Then the table as in the program
    (Origin, Axis, Leg 1..6 with coloured headers, Turn [deg]), merged origin
    cells, borders, bold for entries reading +/-1, the leg cells as live
    formulas = unit ratio x Turn to the chosen decimals; the unit ratios are
    on a hidden sheet.  Written by the built-in _Xlsx writer."""
    import io
    from matplotlib.image import imsave
    X = _Xlsx(decimals)
    U = _Xlsx(6)
    head = header_lines(calc_name, frame_name, rpy_axes, decimals)
    sketches = list(sketches)[:MAX_SKETCHES]
    widths_chars = {1: 18, 2: 9, 3: 11, 4: 11, 5: 11, 6: 11, 7: 11, 8: 11, 9: 11}
    for c, w in widths_chars.items():
        X.width(c, w)
    # --- top section: a fixed block of 9 rows ---
    #   row 1        title (A1:E1 merged, 20 pt)              preview names (F1:G1, H1:I1)
    #   rows 2-3     provenance (A2:E3 merged, wrapped)       previews from row 2 (F onward)
    #   rows 4-9     definition (A4:E9 merged, wrapped)       legend in the Turn column, rows 2-7
    X.row_height(1, 20)
    for rr in range(2, 10):
        X.row_height(rr, 15)
    blocks = [(1, 1), (2, 3), (4, 9)]
    for (r0, r1), line, style in zip(blocks, head, (X.S_TITLE_WRAP, X.S_WRAP, X.S_WRAP)):
        X.cell(r0, 1, line, style)
        X.merge(r0, 1, r1, 5)
    if sketches:
        col_in = X._col_px(6) / 96.0                                    # width of a preview column [in]
        img_h = SKETCH_H_IN
        slot_w = 1.25
        for k, (name, img) in enumerate(sketches):
            buf = io.BytesIO()
            imsave(buf, img, format="png")
            w = min(slot_w, img_h * img.shape[1] / img.shape[0])      # true aspect ratio
            x_in = k * (slot_w + 0.1) + 0.5 * (slot_w - w)             # from column F's left edge
            col = 6 + int(x_in // col_in)
            X.add_image(buf.getvalue(), col, 2, w, img_h, col_off_in=x_in - (col - 6) * col_in)
            X.cell(1, 6 + 2 * k, name, X.S_LABEL)
            X.merge(1, 6 + 2 * k, 1, 7 + 2 * k)
    for j, name in enumerate(LEGS):
        X.cell(2 + j, 9, name, X.S_LEGEND + j)
    r_hdr = 11
    n = len(rows)
    cols = ["Origin", "Axis"] + list(LEGS) + ["Turn [deg]"]
    for c, name in enumerate(cols, start=1):
        X.cell(r_hdr, c, name, X.S_LEG_HDR + (c - 3) if 3 <= c <= 8 else X.S_HEADER)
    for c, name in enumerate(["Origin", "Axis"] + list(LEGS), start=1):
        U.cell(r_hdr, c, name, U.S_HEADER)
    turn_col = 9
    prev_origin = None
    group_start = None
    for k, r in enumerate(rows):
        rr = r_hdr + 1 + k
        first = r["origin"] != prev_origin
        if first:
            if group_start is not None and k - group_start > 1:
                X.merge(r_hdr + 1 + group_start, 1, r_hdr + k, 1)
            group_start = k
            prev_origin = r["origin"]
        X.cell(rr, 1, r["name"] if first else "", X.S_TEXT_C)
        X.cell(rr, 2, r["axis"], X.S_TEXT_C)
        U.cell(rr, 1, r["name"], U.S_TEXT_C)
        U.cell(rr, 2, r["axis"], U.S_TEXT_C)
        units = r["unit"] if "unit" in r else unit_ratios(r, decimals)
        for j, v in enumerate(units):
            bold = _bold(r, j, float(v) * float(_turn(r)), decimals)
            U.cell(rr, 3 + j, float(v), U.S_UNIT_B if bold else U.S_UNIT)
            X.formula(rr, 3 + j, f"'Unit ratios'!{_col_letter(3 + j)}{rr}*${_col_letter(turn_col)}${rr}",
                      X.S_NUM_B if bold else X.S_NUM)
        X.cell(rr, turn_col, float(_turn(r)), X.S_TURN)
    if group_start is not None and n - group_start > 1:
        X.merge(r_hdr + 1 + group_start, 1, r_hdr + n, 1)
    X.cell(r_hdr + n + 2, 1, "Turn [deg] is the input; enter 1.0 to reset a row.", X.S_ITALIC)
    U.width(1, 18); U.width(2, 9)
    for c in range(3, 9):
        U.width(c, 12)
    X.save(path, hidden=U)


def to_png(path, rows, decimals, calc_name, frame_name, rpy_axes, dpi=200, sketches=()):
    """Rendered table (white background, black grid, heavy bold for entries
    reading +/-1, merged origin cells) via matplotlib's Agg backend, sized to
    the content.  The top section has the title and definition on its left
    half (wrapped at that half) and, centred in its right half, up to
    MAX_SKETCHES origin previews (`sketches`: (name, RGBA array) pairs, see
    platform_view.render_sketch_rgba) each with its name above, then a bold,
    leg-coloured legend at the right edge; the Leg column headers carry the
    same colours."""
    from matplotlib import patheffects
    from matplotlib.figure import Figure
    from matplotlib.backends.backend_agg import FigureCanvasAgg
    head = header_lines(calc_name, frame_name, rpy_axes, decimals)
    cols = ["Origin", "Axis"] + list(LEGS) + ["Turn [deg]"]
    n = len(rows)
    col_w = list(TABLE_COL_W)
    row_h = 0.28
    table_w = sum(col_w)
    fig_w = table_w + 0.4
    sketches = list(sketches)[:MAX_SKETCHES]
    # header text wrapped at the left half of the table width
    probe = Figure(figsize=(1, 1), dpi=dpi)
    FigureCanvasAgg(probe)
    pr = probe.canvas.get_renderer()
    limit = 0.5 * table_w - 0.15

    def width_of(text, size, weight):
        tx = probe.text(0, 0, text, fontsize=size, fontweight=weight)
        w = tx.get_window_extent(pr).width / dpi
        tx.remove()
        return w

    wrapped = []
    for i, line in enumerate(head):
        size, weight = (10, "bold") if i == 0 else (7.5, "normal")
        cur = ""
        for word in line.split(" "):
            trial = word if not cur else cur + " " + word
            if cur and width_of(trial, size, weight) > limit:
                wrapped.append((cur, size, weight))
                cur = word
            else:
                cur = trial
        wrapped.append((cur, size, weight))
    text_h = 0.15 + 0.22 * len(wrapped)
    pict_h = (0.12 + SKETCH_LABEL_IN + SKETCH_H_IN) if sketches else 0.0
    top_h = max(text_h, pict_h) + 0.1
    fig_h = top_h + row_h * (n + 1) + 0.3
    fig = Figure(figsize=(fig_w, fig_h), dpi=dpi)
    FigureCanvasAgg(fig)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, fig_w); ax.set_ylim(0, fig_h); ax.set_axis_off()
    y = fig_h - 0.15
    for line, size, weight in wrapped:
        ax.text(0.2, y, line, fontsize=size, fontweight=weight, va="top", ha="left")
        y -= 0.22
    # previews centred in the right half (between the middle and the legend)
    if sketches:
        area_x0 = 0.2 + 0.5 * table_w
        area_x1 = 0.2 + table_w - LEGEND_W_IN
        gap = 0.15
        ws = []
        for _, img in sketches:
            ws.append(min(SKETCH_H_IN * img.shape[1] / img.shape[0],
                          (area_x1 - area_x0 - gap * (len(sketches) + 1)) / len(sketches)))
        total = sum(ws) + gap * (len(sketches) - 1)
        x = 0.5 * (area_x0 + area_x1) - 0.5 * total
        y_img = fig_h - 0.12 - SKETCH_LABEL_IN - SKETCH_H_IN
        for (name, img), w in zip(sketches, ws):
            ax.text(x + 0.5 * w, y_img + SKETCH_H_IN + 0.04, name, fontsize=8, fontweight="bold",
                    ha="center", va="bottom")
            ax_img = fig.add_axes([x / fig_w, y_img / fig_h, w / fig_w, SKETCH_H_IN / fig_h])
            ax_img.imshow(img, aspect="auto", interpolation="lanczos")
            ax_img.set_axis_off()
            x += w + gap
    for j, name in enumerate(LEGS):
        ax.text(0.2 + table_w, fig_h - 0.15 - j * 0.24, name, fontsize=8.5, fontweight="bold",
                color=LEG_COLORS[j], ha="right", va="top")
    y_top = fig_h - top_h
    x_edges = np.concatenate([[0.2], 0.2 + np.cumsum(col_w)])
    y_edges = [y_top - k * row_h for k in range(n + 2)]
    for c, name in enumerate(cols):
        color = LEG_COLORS[c - 2] if 2 <= c <= 7 else "black"
        ax.text(0.5 * (x_edges[c] + x_edges[c + 1]), 0.5 * (y_edges[0] + y_edges[1]), name,
                ha="center", va="center", fontsize=8.5, fontweight="bold", color=color)
    groups = {}
    for k, r in enumerate(rows):
        groups.setdefault(r["origin"], []).append(k)
        yc = 0.5 * (y_edges[k + 1] + y_edges[k + 2])
        ax.text(0.5 * (x_edges[1] + x_edges[2]), yc, r["axis"], ha="center", va="center", fontsize=8.5)
        for j, v in enumerate(_values(r)):
            if _bold(r, j, v, decimals):
                ax.text(x_edges[j + 3] - 0.08, yc, format_value(v, decimals), ha="right", va="center",
                        fontsize=8.5, fontweight="black",
                        path_effects=[patheffects.withStroke(linewidth=0.9, foreground="black")])
            else:
                ax.text(x_edges[j + 3] - 0.08, yc, format_value(v, decimals), ha="right", va="center",
                        fontsize=8.5)
        ax.text(x_edges[9] - 0.08, yc, format_value(_turn(r), TURN_DECIMALS), ha="right", va="center",
                fontsize=8.5)
    sizes = group_sizes(rows)
    for oi, ks in groups.items():
        name = display_name(rows[ks[0]], sizes)
        yc = 0.5 * (y_edges[ks[0] + 1] + y_edges[ks[-1] + 2])
        ax.text(0.5 * (x_edges[0] + x_edges[1]), yc, name, ha="center", va="center", fontsize=8.5,
                linespacing=1.1)
    lw = 0.8
    ax.plot([x_edges[0], x_edges[-1]], [y_edges[0], y_edges[0]], color="k", lw=lw)
    ax.plot([x_edges[0], x_edges[-1]], [y_edges[1], y_edges[1]], color="k", lw=lw)
    ax.plot([x_edges[0], x_edges[-1]], [y_edges[-1], y_edges[-1]], color="k", lw=lw)
    for xe in x_edges:
        ax.plot([xe, xe], [y_edges[0], y_edges[-1]], color="k", lw=lw)
    for k in range(1, n):
        is_group_edge = rows[k]["origin"] != rows[k - 1]["origin"]
        x0 = x_edges[0] if is_group_edge else x_edges[1]
        ax.plot([x0, x_edges[-1]], [y_edges[k + 1], y_edges[k + 1]], color="k",
                lw=lw if is_group_edge else 0.4)
    fig.savefig(path, dpi=dpi, facecolor="white")
