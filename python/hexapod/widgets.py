"""
Input boxes with standard clipboard behaviour and instant rounding.

A QLineEdit copies, cuts and pastes with the platform shortcuts (Ctrl+C /
Ctrl+V on Windows and Linux, Cmd+C / Cmd+V on macOS) on its own, but a
validator vets a paste as a whole: text copied from a spreadsheet cell (which
carries a trailing newline) or a value with more than three decimals is
rejected outright and nothing appears.  The classes here use no validator and
instead react to every user edit (typing and every paste route: shortcut,
context menu, middle-click, drag and drop) through textEdited, which Qt does
not emit for programmatic setText():

- NumberLineEdit : a pasted or typed value with more than the box's decimals is
                   rounded at once (1.0011109 -> 1.001); whitespace, newlines,
                   exponents and a Unicode minus are accepted and normalised;
                   text that cannot become a number is refused (the previous
                   text is restored) except for the partial entries "", "-",
                   "1." that are on the way to a number.  Leaving the box (Tab,
                   Enter, focus change) normalises to the fixed format.
- IntLineEdit    : same for an integer box with a range (clamped).
- NameLineEdit   : text box with a maximum length; forbidden characters are
                   removed and pastes are truncated instead of refused.
"""
from __future__ import annotations
import re
from PySide6.QtWidgets import QLineEdit

_PARTIAL = re.compile(r"^[-+]?\d*\.?\d*(?:[eE][-+]?\d*)?$")


def parse_number(text):
    """Float value of pasted/typed text, or None.  Tolerates surrounding
    whitespace and newlines (spreadsheet cells) and a Unicode minus sign."""
    if text is None:
        return None
    s = str(text).strip().replace("\u2212", "-")
    if not s:
        return None
    try:
        v = float(s)
    except ValueError:
        return None
    if v != v or v in (float("inf"), float("-inf")):
        return None
    return v


def _canonical(text, decimals):
    """True when `text` is already exactly in the %.{decimals}f layout."""
    return re.fullmatch(r"-?\d+\.\d{%d}" % decimals, text) is not None


class NumberLineEdit(QLineEdit):
    """Fixed-decimal numeric box (default three decimals)."""

    def __init__(self, text="0.000", parent=None, decimals=3):
        super().__init__(text, parent)
        self._decimals = int(decimals)
        self._last_good = text
        self.textEdited.connect(self._on_edited)
        self.editingFinished.connect(self._normalise)

    def _format(self, value):
        return f"{round(float(value), self._decimals):.{self._decimals}f}"

    def _on_edited(self, text):
        clean = text.replace("\u2212", "-")
        value = parse_number(clean)
        if value is not None:
            if _canonical(clean, self._decimals) or self._is_short_decimal(clean):
                self._last_good = clean               # typed as is, still exact
                if clean != text:
                    self._replace(clean)
            else:
                self._replace(self._format(value))    # more decimals / spaces / exponent
            return
        if _PARTIAL.fullmatch(clean.strip()):
            self._last_good = clean.strip()           # on the way to a number
            if clean.strip() != text:
                self._replace(clean.strip())
            return
        self._replace(self._last_good)                # not a number: refuse

    def _is_short_decimal(self, text):
        """Plain decimal with at most the box's decimals (no exponent, no
        surrounding whitespace), e.g. '5', '-1.2', '3.141'."""
        m = re.fullmatch(r"[-+]?(?:\d+\.?\d*|\.\d+)", text)
        if not m:
            return False
        frac = text.split(".")[1] if "." in text else ""
        return len(frac) <= self._decimals

    def _replace(self, new_text):
        if new_text != self.text():
            self.setText(new_text)
            self.setCursorPosition(len(new_text))
        self._last_good = new_text

    def _normalise(self):
        value = parse_number(self.text())
        if value is not None:
            self._replace(self._format(value))


class IntLineEdit(QLineEdit):
    """Integer box with a range; a pasted or typed value is rounded and clamped."""

    def __init__(self, text="1", parent=None, lo=1, hi=360):
        super().__init__(text, parent)
        self._lo, self._hi = int(lo), int(hi)
        self._last_good = text
        self.textEdited.connect(self._on_edited)
        self.editingFinished.connect(self._normalise)

    def _clamp(self, value):
        return str(min(max(int(round(value)), self._lo), self._hi))

    def _on_edited(self, text):
        value = parse_number(text)
        if value is not None:
            new = self._clamp(value)
            if new != text:
                self.setText(new)
                self.setCursorPosition(len(new))
            self._last_good = new
        elif text.strip() in ("", "-"):
            self._last_good = text.strip()
        else:
            self.setText(self._last_good)
            self.setCursorPosition(len(self._last_good))

    def _normalise(self):
        value = parse_number(self.text())
        if value is None:
            value = self._lo
        self.setText(self._clamp(value))
        self._last_good = self.text()


class NameLineEdit(QLineEdit):
    """Text box limited to `max_len` characters that may not contain the
    characters in `forbidden` (the apostrophe delimits names in formdata.txt).
    Forbidden characters are removed and newlines collapsed on every edit;
    QLineEdit's maxLength truncates over-long typing and pastes."""

    def __init__(self, text="", parent=None, max_len=15, forbidden="'"):
        super().__init__(str(text)[:max_len], parent)
        self._max_len = int(max_len)
        self._forbidden = forbidden
        self.setMaxLength(self._max_len)
        self.textEdited.connect(self._on_edited)

    def _on_edited(self, text):
        clean = " ".join(text.split()) if ("\n" in text or "\t" in text or "\r" in text) else text
        for ch in self._forbidden:
            clean = clean.replace(ch, "")
        clean = clean[:self._max_len]
        if clean != text:
            pos = min(self.cursorPosition(), len(clean))
            self.setText(clean)
            self.setCursorPosition(pos)
