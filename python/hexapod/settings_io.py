"""Read / validate / write the strict formdata.txt settings file.

Faithful port of load_data.m and save_data.m.  The on-disk format is identical
in the MATLAB tool:

    <tag> = <value with exactly 3 decimals>      (76 numeric lines, config.TAGS order)
    calculator_name = '<name>'
    rpy_axes = 'ZXY'                              (optional: which axis roll, pitch,
                                                   yaw rotate about; default XYZ)
    origin_1 = 'Origin 1', 0.000, 0.000, 0.000, 0.000, 0.000, 0.000   (optional block)
    origin_2 = '<name up to 22 chars>', <dx>, <dy>, <dz>, <roll>, <pitch>, <yaw>
    ...
    origin_active = <k>                           (1 <= k <= number of origin lines)
    adj_decimals = 3                              (optional block: the Incremental
    adj_1 = 'XYZ---', 1.0, 1.0, 1.0, 1.0, 1.0, 1.0   Adj. Table set-up, one line per
    adj_2 = '---RPW', 15.0, 1.0, 1.0, 1.0, 1.0, 1.0  origin: ticked-axis mask, six turns)

Every base and platform joint carries its own X, Y, Z.  An origin (point of
interest) is a full frame: its offset X, Y, Z [mm] and its orientation roll,
pitch, yaw [deg] relative to Origin 1 (angles about the rpy axes).  The origin
block and the rpy_axes line are only written when they carry information; the
number of origins is simply the number of origin_k lines.  The numeric values
are always stored exactly as displayed, i.e. in the frame of the ACTIVE origin.

Numbers are written with exactly three decimals.  When READING, any decimal
number is accepted on a value line (e.g. a hand-edited "1.0011109" or "5") and
rounded to three decimals.  Two older layouts are also read and converted
forward: the 69-tag layout with a single Base Z / Platform Z plane height and
three bench values (config.LEGACY_TAGS: every joint receives the plane height,
the bench values are dropped), an "origin_count = N" line ahead of the origin
lines (ignored), and origin lines with only the three offsets (orientation
taken as zero).  read_settings() returns the list of reasons the file differs
from the canonical layout so the caller can rewrite it at start-up.
"""
from __future__ import annotations
import os
import re
from . import config


def default_values_dict():
    return dict(zip(config.TAGS, config.DEFAULT_VALUES))


def convert_legacy_values(old):
    """Map a 69-tag (plane-height) value dict onto the per-joint-Z layout.

    base{i}z <- baseZ, plat{i}z <- platZheight; benchZheight, benchThickness
    and platToBenchBottomZ are dropped (they no longer exist in the program).
    """
    new = {}
    for i in range(1, 7):
        new[f"base{i}x"] = old[f"base{i}x"]
        new[f"base{i}y"] = old[f"base{i}y"]
        new[f"base{i}z"] = old["baseZ"]
    for i in range(1, 7):
        new[f"plat{i}x"] = old[f"plat{i}x"]
        new[f"plat{i}y"] = old[f"plat{i}y"]
        new[f"plat{i}z"] = old["platZheight"]
    for tag in config.TAGS:
        if tag not in new:
            new[tag] = old[tag]
    return new


# ---------------------------------------------------------------------------
# Origins / points of interest
# ---------------------------------------------------------------------------
ORIGIN_NAME_MAX = config.ORIGIN_NAME_MAX

# A decimal number as accepted on a value line: optional sign, digits, optional
# fraction of any length, optional exponent.  Written back as %.3f.
NUMBER = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"
DEFAULT_ORIGIN_NAME = config.DEFAULT_ORIGIN_NAME


ORIGIN_KEYS = ("dx", "dy", "dz", "roll", "pitch", "yaw")


def default_origins():
    """The single reference origin (offset and orientation fixed at zero)."""
    return [dict(name=DEFAULT_ORIGIN_NAME, dx=0.0, dy=0.0, dz=0.0,
                 roll=0.0, pitch=0.0, yaw=0.0)]


# ---- Incremental Adjustment Table set-up ----
# Stored per origin (list order) as a six-character mask over X, Y, Z, Roll,
# Pitch, Yaw ('-' = not ticked; the letters X Y Z R P W mark ticked axes) and
# the six turn multipliers [deg, one decimal], plus the decimal places.
ADJ_AXES = ("X", "Y", "Z", "Roll", "Pitch", "Yaw")
ADJ_MASK_LETTERS = "XYZRPW"
ADJ_DEFAULT_DECIMALS = 3
ADJ_DEFAULT_TURN = 1.0


def default_adj_config(n_origins=1):
    """Nothing ticked, all turns 1.0, three decimals."""
    return dict(decimals=ADJ_DEFAULT_DECIMALS,
                rows=[dict(axes=set(), turns=[ADJ_DEFAULT_TURN] * 6) for _ in range(n_origins)])


def normalise_adj_config(cfg, n_origins):
    """One row per origin (truncate or pad), valid axes, turns rounded to one
    decimal, decimals in 0..6."""
    cfg = cfg or {}
    try:
        dec = int(cfg.get("decimals", ADJ_DEFAULT_DECIMALS))
    except (TypeError, ValueError):
        dec = ADJ_DEFAULT_DECIMALS
    dec = min(max(dec, 0), 6)
    rows = []
    for i in range(n_origins):
        src = cfg.get("rows", [])[i] if i < len(cfg.get("rows", [])) else {}
        axes = {a for a in (src.get("axes") or ()) if a in ADJ_AXES}
        turns = list(src.get("turns") or [])[:6]
        turns += [ADJ_DEFAULT_TURN] * (6 - len(turns))
        clean = []
        for t in turns:
            try:
                v = round(float(t), 1)
            except (TypeError, ValueError):
                v = ADJ_DEFAULT_TURN
            if v != v:
                v = ADJ_DEFAULT_TURN
            clean.append(max(-99999.9, min(99999.9, v)))
        rows.append(dict(axes=axes, turns=clean))
    return dict(decimals=dec, rows=rows)


def adj_config_is_default(cfg):
    if int(cfg.get("decimals", ADJ_DEFAULT_DECIMALS)) != ADJ_DEFAULT_DECIMALS:
        return False
    for r in cfg.get("rows", []):
        if r.get("axes") or any(abs(t - ADJ_DEFAULT_TURN) > 0 for t in r.get("turns", [])):
            return False
    return True


def adj_mask(axes):
    return "".join(ADJ_MASK_LETTERS[i] if a in axes else "-" for i, a in enumerate(ADJ_AXES))


def adj_axes_from_mask(mask):
    return {a for i, a in enumerate(ADJ_AXES) if mask[i] != "-"}


def normalise_rpy_axes(axes):
    axes = str(axes or config.RPY_AXES_DEFAULT).upper().strip()
    return axes if axes in config.RPY_AXES_OPTIONS else config.RPY_AXES_DEFAULT


def normalise_origins(origins, active):
    """Return a cleaned (origins, active) pair that always satisfies the
    invariants: at least one origin, Origin 1 offset and orientation == 0,
    names 1..ORIGIN_NAME_MAX chars with no apostrophe, values rounded to 3 decimals,
    1 <= active <= N."""
    out = []
    for i, o in enumerate(origins or []):
        name = str(o.get("name", "")).replace("'", "").strip()
        if not name:
            name = DEFAULT_ORIGIN_NAME if i == 0 else f"Origin {i + 1}"
        name = name[:ORIGIN_NAME_MAX]
        entry = dict(name=name)
        for k in ORIGIN_KEYS:
            entry[k] = 0.0 if i == 0 else round(float(o.get(k, 0.0)), 3)
        out.append(entry)
    if not out:
        out = default_origins()
    try:
        active = int(active)
    except (TypeError, ValueError):
        active = 1
    if not 1 <= active <= len(out):
        active = 1
    return out, active


def origins_block_needed(origins, active):
    """True when the trailing origin block carries information."""
    return (len(origins) > 1 or int(active) != 1
            or origins[0]["name"] != DEFAULT_ORIGIN_NAME)


def fmt(value):
    """Format a number exactly like MATLAB '%.3f'."""
    return f"{float(value):.3f}"


def write_settings(path, values, name, origins=None, active=1, rpy_axes=None, adj_config=None):
    """Write all numeric tags (3 decimals), the calculator_name line, the
    rpy_axes line (when not the default), the origin block and the Incremental
    Adj. Table block (each only when it carries information).

    Mirrors save_data.m, including its fallback to formdata_new.txt when the
    primary file cannot be opened.
    """
    origins, active = normalise_origins(origins or default_origins(), active)
    rpy_axes = normalise_rpy_axes(rpy_axes)
    adj = normalise_adj_config(adj_config, len(origins))
    try:
        f = open(path, "w", newline="\n")
    except OSError:
        fallback = os.path.join(os.path.dirname(path) or ".", "formdata_new.txt")
        f = open(fallback, "w", newline="\n")
        path = fallback
    with f:
        for tag in config.TAGS:
            f.write(f"{tag} = {fmt(values[tag])}\n")
        f.write(f"calculator_name = '{name}'\n")
        if rpy_axes != config.RPY_AXES_DEFAULT:
            f.write(f"rpy_axes = '{rpy_axes}'\n")
        if origins_block_needed(origins, active):
            for i, o in enumerate(origins):
                f.write(f"origin_{i + 1} = '{o['name']}', "
                        + ", ".join(fmt(o[k]) for k in ORIGIN_KEYS) + "\n")
            f.write(f"origin_active = {active}\n")
        if not adj_config_is_default(adj):
            f.write(f"adj_decimals = {adj['decimals']}\n")
            for i, r in enumerate(adj["rows"]):
                f.write(f"adj_{i + 1} = '{adj_mask(r['axes'])}', "
                        + ", ".join(f"{t:.1f}" for t in r["turns"]) + "\n")
    return path


def write_defaults(path):
    write_settings(path, default_values_dict(), config.DEFAULT_NAME)


def _is_legacy_layout(raw_lines):
    """The per-joint-Z layout has 'base1z = ...' on line 3; the old plane-height
    layout has 'base2x = ...' there.  Used to pick the tag list to validate
    against (a file that matches neither is reported against the current one)."""
    return len(raw_lines) >= 3 and raw_lines[2].startswith("base2x = ")


def _validate(raw_lines):
    """Validate raw text lines.

    Returns (values_dict, name, origins, active, rpy_axes, adj_config, rewrite_reasons, errors_list).
    `rewrite_reasons` lists why the file should be rewritten in the canonical
    layout (older tag layout, origin_count line, values not at three
    decimals); empty when the file is already canonical.  The origin block is
    optional: a plain numeric-lines + calculator_name file yields the default
    single origin.
    """
    legacy = _is_legacy_layout(raw_lines)
    reasons = []
    if legacy:
        reasons.append("older layout (single Base Z / Platform Z plane height and "
                       "bench values): each joint now has its own Z, bench values dropped")
    rounded = False
    tags = config.LEGACY_TAGS if legacy else config.TAGS
    n = len(tags)
    total = n + 1
    values = {}
    errors = []
    name = config.DEFAULT_NAME
    origins = default_origins()
    active = 1
    rpy_axes = config.RPY_AXES_DEFAULT
    adj = None

    if len(raw_lines) < total:
        errors.append(f"Expected at least {total} lines but found {len(raw_lines)}.")

    for i in range(min(n, len(raw_lines))):
        tag = tags[i]
        pat = rf"^{re.escape(tag)} = ({NUMBER})$"
        m = re.match(pat, raw_lines[i])
        if not m:
            errors.append(f"Line {i + 1}: '{raw_lines[i]}'  - Expected: '{tag} = -123.456'")
        else:
            v = round(float(m.group(1)), 3)
            values[tag] = v
            if fmt(v) != m.group(1):
                rounded = True

    if len(raw_lines) >= n + 1:
        m = re.match(r"^calculator_name = '(.{1,100})'$", raw_lines[n])
        if not m:
            errors.append(f"Line {n + 1}: '{raw_lines[n]}'  - Expected: \"calculator_name = '...'\"")
        else:
            name = m.group(1)

    # ---- optional origin block ----
    # origin_1 .. origin_N lines (consecutive, numbered from 1) followed by
    # "origin_active = k".  An older "origin_count = N" line ahead of them is
    # accepted and ignored.  Anything else after calculator_name is an error.
    idx = total
    # optional rotation-angle axes line
    if idx < len(raw_lines) and raw_lines[idx].startswith("rpy_axes"):
        m = re.match(r"^rpy_axes = '([A-Za-z]{3})'$", raw_lines[idx])
        if not m or m.group(1).upper() not in config.RPY_AXES_OPTIONS:
            errors.append(f"Line {idx + 1}: '{raw_lines[idx]}'  - Expected: "
                          f"\"rpy_axes = 'XYZ'\" (one of {', '.join(config.RPY_AXES_OPTIONS)})")
        else:
            rpy_axes = m.group(1).upper()
            if m.group(1) != rpy_axes or rpy_axes == config.RPY_AXES_DEFAULT:
                reasons.append("rpy_axes line normalised")
        idx += 1
    if idx < len(raw_lines) and re.match(r"^origin_count = \d+$", raw_lines[idx]):
        reasons.append("origin_count line (the number of origins is the number of origin lines)")
        idx += 1
    parsed = []
    pat = (r"^origin_(\d+) = '([^']{1," + str(ORIGIN_NAME_MAX) + r"})', (" + NUMBER +
           r"), (" + NUMBER + r"), (" + NUMBER + r")(?:, (" + NUMBER + r"), (" + NUMBER +
           r"), (" + NUMBER + r"))?$")
    short_origin = False
    while idx < len(raw_lines) and raw_lines[idx].startswith("origin_") \
            and not raw_lines[idx].startswith("origin_active"):
        m = re.match(pat, raw_lines[idx])
        if not m or int(m.group(1)) != len(parsed) + 1:
            errors.append(f"Line {idx + 1}: '{raw_lines[idx]}'  - Expected: "
                          f"\"origin_{len(parsed) + 1} = 'Name', 0.000, 0.000, 0.000, 0.000, 0.000, 0.000\"")
            idx += 1
            continue
        if m.group(6) is None:
            short_origin = True                       # offsets only: orientation 0
            groups = (3, 4, 5)
        else:
            groups = (3, 4, 5, 6, 7, 8)
        vals6 = [round(float(m.group(k)), 3) for k in groups] + [0.0] * (6 - len(groups))
        if any(fmt(v) != m.group(k) for v, k in zip(vals6, groups)):
            rounded = True
        parsed.append(dict(name=m.group(2), **dict(zip(ORIGIN_KEYS, vals6))))
        idx += 1
    if parsed:
        if idx < len(raw_lines):
            m = re.match(r"^origin_active = (\d+)$", raw_lines[idx])
            if not m or not (1 <= int(m.group(1)) <= len(parsed)):
                errors.append(f"Line {idx + 1}: '{raw_lines[idx]}'  - Expected: "
                              f"'origin_active = 1' (1..{len(parsed)})")
            else:
                active = int(m.group(1))
            idx += 1
        else:
            errors.append(f"Line {idx + 1}: missing 'origin_active = k' after the origin lines.")
        if any(abs(parsed[0][k]) > 0 for k in ORIGIN_KEYS):
            errors.append(f"Line {total + 1}: Origin 1 must have a zero offset and "
                          f"orientation (it is the reference origin).")
        if short_origin:
            reasons.append("origin lines without an orientation (roll, pitch, yaw taken as 0)")
        origins = parsed
    # optional Incremental Adj. Table block: adj_decimals then adj_1 .. adj_N
    if idx < len(raw_lines) and raw_lines[idx].startswith("adj_"):
        adj = default_adj_config(len(origins))
        m = re.match(r"^adj_decimals = (\d)$", raw_lines[idx])
        if not m:
            errors.append(f"Line {idx + 1}: '{raw_lines[idx]}'  - Expected: 'adj_decimals = 3'")
        else:
            adj["decimals"] = int(m.group(1))
        idx += 1
        pat = (r"^adj_(\d+) = '([" + ADJ_MASK_LETTERS + r"\-]{6})'" + "".join(", (" + NUMBER + ")" for _ in range(6)) + "$")
        k = 0
        while idx < len(raw_lines) and raw_lines[idx].startswith("adj_"):
            m = re.match(pat, raw_lines[idx])
            if not m or int(m.group(1)) != k + 1:
                errors.append(f"Line {idx + 1}: '{raw_lines[idx]}'  - Expected: "
                              f"\"adj_{k + 1} = 'XYZRPW', 1.0, 1.0, 1.0, 1.0, 1.0, 1.0\"")
                idx += 1
                continue
            if k < len(adj["rows"]):
                adj["rows"][k] = dict(axes=adj_axes_from_mask(m.group(2)),
                                      turns=[round(float(m.group(3 + j)), 1) for j in range(6)])
            else:
                reasons.append("adj_k lines beyond the number of origins dropped")
            k += 1
            idx += 1
        if k < len(origins):
            reasons.append("adj_k lines missing for some origins (nothing ticked for them)")
    if idx < len(raw_lines):
        errors.append(f"Line {idx + 1}: '{raw_lines[idx]}'  - Unexpected extra line "
                      f"(only rpy_axes / origin_k / origin_active / adj_k lines may follow calculator_name).")

    if not errors and legacy:
        values = convert_legacy_values(values)
    if rounded:
        reasons.append("values rounded to three decimals")
    origins, active = normalise_origins(origins, active)
    adj = normalise_adj_config(adj, len(origins))
    return values, name, origins, active, rpy_axes, adj, reasons, errors


def read_settings(path):
    """Read and validate the settings file.

    Returns one of:
        ("missing",)                                    file does not exist
        ("corrupt", errors, preview_text)               file present but invalid
        ("ok", values_dict, name, origins, active, rpy_axes, adj_config, rewrite_reasons)
              file present and valid; rewrite_reasons is a list of strings
              (empty when the file is already in the canonical layout) telling
              why the caller should rewrite it: older layout converted forward,
              origin_count line, values rounded to three decimals
    """
    if not os.path.isfile(path):
        return ("missing",)

    with open(path, "r") as f:
        raw_lines = [ln.rstrip("\n").strip() for ln in f.readlines()]

    values, name, origins, active, rpy_axes, adj, reasons, errors = _validate(raw_lines)
    if errors:
        preview_count = min(4, len(errors))
        preview = "\n".join(errors[:preview_count])
        if len(errors) > preview_count:
            preview += f"\n...and {len(errors) - preview_count} more invalid lines"
        return ("corrupt", errors, preview)

    return ("ok", values, name, origins, active, rpy_axes, adj, reasons)
