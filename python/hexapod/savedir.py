"""
Remembered save location, shared by every file dialog in the program.

The first dialog of a session starts where the program starts (the folder of
the executable or script).  After any save, export or folder choice the
folder used is remembered, and every later dialog starts there, whichever
button or window opened it.  If that folder no longer exists (removed drive,
deleted folder) the nearest existing parent is used, and finally the start
folder again, so a dialog always opens somewhere valid.
"""
from __future__ import annotations
import os
import sys

_last_dir = None


def default_dir():
    """Where the program starts: the folder of the executable or script,
    falling back to the working directory."""
    for root in (os.path.dirname(os.path.abspath(sys.argv[0])), os.getcwd()):
        if root and os.path.isdir(root):
            return root
    return os.getcwd()


def _nearest_existing(path):
    p = os.path.abspath(path)
    seen = set()
    while p and p not in seen:
        if os.path.isdir(p):
            return p
        seen.add(p)
        parent = os.path.dirname(p)
        if parent == p:
            break
        p = parent
    return None


def start_dir():
    """The folder a file dialog should open in."""
    global _last_dir
    if _last_dir:
        found = _nearest_existing(_last_dir)
        if found:
            return found
        _last_dir = None
    return default_dir()


def start_path(filename):
    """start_dir() joined with a suggested file name."""
    return os.path.join(start_dir(), filename)


def remember(path):
    """Record the folder of a file (or a folder) that was just used."""
    global _last_dir
    if not path:
        return
    p = os.path.abspath(path)
    folder = p if os.path.isdir(p) else os.path.dirname(p)
    if folder and os.path.isdir(folder):
        _last_dir = folder
