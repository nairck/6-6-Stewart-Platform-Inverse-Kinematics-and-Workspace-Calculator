#!/usr/bin/env bash
# =============================================================================
#  Hexapod Calculator - Linux build
#
#     chmod +x build_linux.sh
#     ./build_linux.sh
#
#  Produces ONE double-clickable file:  HexapodCalculator-x86_64.AppImage
#
#  It contains the program, Python, Qt, VTK and the X/xcb libraries Qt loads at
#  run time, so the machine it runs on needs nothing installed: no Python, no
#  apt packages.  It also carries the icon, which a plain Linux executable
#  cannot, so file managers show it properly.
#
#  This script installs whatever the BUILD machine is missing (it will ask for
#  your password once).  On a distro without apt it prints the package list and
#  carries on.
#
#  One rule for public releases: glibc is forward compatible only, so build on
#  the oldest system you want to support.  An AppImage built on Ubuntu 22.04
#  runs on 22.04 and everything newer.  See README.md for a one-line Docker way
#  to do that without installing anything.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

APP=HexapodCalculator
ARCH="$(uname -m)"
OUT="dist/$APP"                 # no .AppImage extension: it is not required

PKGS="python3-venv python3-pip python3-dev python3-tk binutils patchelf file wget \
libxcb-cursor0 libxcb-xinerama0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-shm0 libxcb-sync1 \
libxcb-xfixes0 libxcb-xkb1 libx11-xcb1 libxkbcommon-x11-0 libxkbcommon0 \
libgl1 libegl1 libglu1-mesa libdbus-1-3 libfontconfig1 libfreetype6 \
libxrender1 libxi6 libsm6 libice6"

echo "[1/7] Build tools and libraries..."
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq
    # shellcheck disable=SC2086
    sudo apt-get install -y $PKGS
else
    echo "  no apt on this system; make sure the equivalents of these are installed:"
    echo "  $PKGS"
fi

test -f requirements.txt || { echo "ERROR: run this from the python/ folder"; exit 1; }
test -f assets/icon.png   || { echo "ERROR: assets/icon.png is missing"; exit 1; }

echo "[2/7] Virtual environment and Python dependencies..."
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

echo "[3/7] Compiling with PyInstaller..."
# everything intermediate goes under build/, so dist/ only ever holds the AppImage
rm -rf build AppDir "$OUT"
HEXAPOD_ONEFILE=0 python -m PyInstaller --clean --noconfirm \
    --distpath build/payload --workpath build/work hexapod.spec
test -d "build/payload/$APP" || { echo "ERROR: expected build/payload/$APP"; exit 1; }

echo "[4/7] Assembling the AppDir..."
mkdir -p dist AppDir/usr/bin AppDir/usr/lib AppDir/usr/share/applications \
         AppDir/usr/share/icons/hicolor/256x256/apps
cp -a "build/payload/$APP/." AppDir/usr/bin/
# formdata.txt is deliberately NOT bundled: the copy inside the read-only mount
# would shadow the user's own file next to the AppImage.  The program writes a
# default one on first run.

# Qt opens these with dlopen, so PyInstaller cannot see them.  They go last on
# the library path at run time, so a newer system copy always wins.
for lib in libxcb-cursor.so.0 libxcb-xinerama.so.0 libxcb-icccm.so.4 \
           libxcb-image.so.0 libxcb-keysyms.so.1 libxcb-randr.so.0 \
           libxcb-render-util.so.0 libxcb-shape.so.0 libxcb-shm.so.0 \
           libxcb-sync.so.1 libxcb-xfixes.so.0 libxcb-xkb.so.1 \
           libxkbcommon.so.0 libxkbcommon-x11.so.0 libX11-xcb.so.1; do
    p="$(ldconfig -p | awk -v l="$lib" '$1 == l {print $NF; exit}')" || true
    [ -n "${p:-}" ] && [ -f "$p" ] && cp -L "$p" AppDir/usr/lib/ || echo "  note: $lib not found, skipped"
done

echo "[5/7] Launcher, metadata and icon..."
cat > AppDir/AppRun <<'RUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"

# ---------------------------------------------------------------------------
#  Give this file its own icon in every file manager.
#
#  A Linux executable has nowhere to store an icon, and file managers pick
#  icons by MIME type, so the program registers a MIME type for itself the
#  first time it runs and attaches its icon to it.  Nothing is added to the
#  desktop or the applications menu.  Costs nothing on later runs, and
#  "--uninstall-icon" undoes it.
# ---------------------------------------------------------------------------
MIME_DIR="$HOME/.local/share/mime"
ICON_DIR="$HOME/.local/share/icons/hicolor"
MIME_XML="$MIME_DIR/packages/hexapod-calculator.xml"
# Icon lookup is driven by the size being asked for, and the desktop asks at a
# small size while file managers ask at larger ones, so the icon goes into
# every size folder.  The same PNG is used throughout; the toolkit scales it.
ICON_SIZES="16x16 22x22 24x24 32x32 48x48 64x64 128x128 256x256"
ICON_NAME=application-x-hexapod-calculator

icons_present() {
    for sz in $ICON_SIZES; do
        [ -f "$ICON_DIR/$sz/mimetypes/$ICON_NAME.png" ] || return 1
    done
    return 0
}

register_icon() {
    [ -f "$MIME_XML" ] && icons_present && return 0        # already done
    mkdir -p "$MIME_DIR/packages" 2>/dev/null || return 0
    for sz in $ICON_SIZES; do
        mkdir -p "$ICON_DIR/$sz/mimetypes" 2>/dev/null || return 0
        cp "$HERE/HexapodCalculator.png" "$ICON_DIR/$sz/mimetypes/$ICON_NAME.png" 2>/dev/null || return 0
    done
    cat > "$MIME_XML" <<'MIMEXML'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-hexapod-calculator">
    <comment>Hexapod Calculator</comment>
    <!-- Still an executable, or the desktop forgets the file can be run and
         asks which program should open it. -->
    <sub-class-of type="application/x-executable"/>
    <!-- Both names are stated explicitly: some desktops derive the icon name
         from the type, others only honour these elements. -->
    <icon name="application-x-hexapod-calculator"/>
    <generic-icon name="application-x-hexapod-calculator"/>
    <glob pattern="HexapodCalculator*" weight="100"/>
  </mime-type>
</mime-info>
MIMEXML
    [ -f "$ICON_DIR/index.theme" ] || cp /usr/share/icons/hicolor/index.theme "$ICON_DIR/index.theme" 2>/dev/null || true
    command -v update-mime-database  >/dev/null 2>&1 && update-mime-database "$MIME_DIR" >/dev/null 2>&1 || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$ICON_DIR" >/dev/null 2>&1 || true
    # The desktop is a separate process from the file manager and keeps its own
    # icon cache, so it is restarted; open folders are untouched.
    if command -v xfdesktop >/dev/null 2>&1 && pgrep -x xfdesktop >/dev/null 2>&1; then
        (xfdesktop --quit >/dev/null 2>&1; sleep 1; setsid xfdesktop >/dev/null 2>&1 &) || true
    fi
}

if [ "${1:-}" = "--uninstall-icon" ]; then
    rm -f "$MIME_XML"
    for sz in $ICON_SIZES; do
        rm -f "$ICON_DIR/$sz/mimetypes/$ICON_NAME.png"
    done
    command -v update-mime-database >/dev/null 2>&1 && update-mime-database "$MIME_DIR" >/dev/null 2>&1 || true
    echo "Icon registration removed."
    exit 0
fi

register_icon
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:$HERE/usr/lib"
# Start in the folder the user launched from; settings are read and written
# next to this file (the program uses $APPIMAGE for that).
cd "${OWD:-$PWD}" || true
exec "$HERE/usr/bin/HexapodCalculator" "$@"
RUN
chmod +x AppDir/AppRun

cat > "AppDir/$APP.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Hexapod Calculator
Comment=Hexapod inverse kinematics and workspace solver
Exec=HexapodCalculator
Icon=HexapodCalculator
Categories=Science;Engineering;
Terminal=false
DESK
cp "AppDir/$APP.desktop" AppDir/usr/share/applications/
cp assets/icon.png "AppDir/$APP.png"
cp assets/icon.png "AppDir/usr/share/icons/hicolor/256x256/apps/$APP.png"

echo "[6/7] Packing the AppImage..."
TOOL="./.appimagetool-$ARCH.AppImage"   # hidden: a cache, not an output
if [ ! -x "$TOOL" ]; then
    echo "      fetching appimagetool (once)..."
    wget -q --show-progress -O "$TOOL" \
      "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$ARCH.AppImage" \
      || { rm -f "$TOOL"; echo "ERROR: could not download appimagetool (no internet?)"; exit 1; }
    chmod +x "$TOOL"
fi
ARCH="$ARCH" "$TOOL" --appimage-extract-and-run AppDir "$OUT"
chmod +x "$OUT"

echo "[7/7] Registering the icon on this machine..."
DIST="$(cd dist && pwd)"
ICONS="$HOME/.local/share/icons/hicolor"
MIME="$HOME/.local/share/mime"
MIME_XML="$MIME/packages/hexapod-calculator.xml"
ICON_NAME=application-x-hexapod-calculator
ICON_SIZES="16x16 22x22 24x24 32x32 48x48 64x64 128x128 256x256"

need=0
[ -f "$MIME_XML" ] || need=1
for sz in $ICON_SIZES; do
    cmp -s assets/icon.png "$ICONS/$sz/mimetypes/$ICON_NAME.png" || need=1
done

if [ "$need" = 1 ]; then
    mkdir -p "$MIME/packages"
    for sz in $ICON_SIZES; do
        mkdir -p "$ICONS/$sz/mimetypes"
        cp assets/icon.png "$ICONS/$sz/mimetypes/$ICON_NAME.png"
    done
    cat > "$MIME_XML" <<'MIMEXML'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-hexapod-calculator">
    <comment>Hexapod Calculator</comment>
    <!-- Still an executable, or the desktop forgets the file can be run and
         asks which program should open it. -->
    <sub-class-of type="application/x-executable"/>
    <!-- Both names are stated explicitly: some desktops derive the icon name
         from the type, others only honour these elements. -->
    <icon name="application-x-hexapod-calculator"/>
    <generic-icon name="application-x-hexapod-calculator"/>
    <glob pattern="HexapodCalculator*" weight="100"/>
  </mime-type>
</mime-info>
MIMEXML
    [ -f "$ICONS/index.theme" ] || cp /usr/share/icons/hicolor/index.theme "$ICONS/index.theme" 2>/dev/null || true
    command -v update-mime-database  >/dev/null && update-mime-database "$MIME" >/dev/null 2>&1 || true
    command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t "$ICONS" >/dev/null 2>&1 || true
    if command -v xfdesktop >/dev/null 2>&1 && pgrep -x xfdesktop >/dev/null 2>&1; then
        (xfdesktop --quit >/dev/null 2>&1; sleep 1; setsid xfdesktop >/dev/null 2>&1 &) || true
        echo "      registered; the desktop was restarted to pick it up"
    else
        echo "      registered (this happens once; later builds leave it alone)"
    fi
else
    echo "      already registered, nothing to refresh"
fi

# Remove the launchers and menu entries earlier versions of this script created:
# the program is meant to be one portable file, nothing else.
rm -f "$DIST/Hexapod Calculator.desktop" "$DIST/.HexapodCalculator.png" \
      "$HOME/Desktop/Hexapod Calculator.desktop" \
      "$HOME/.local/share/applications/hexapod-calculator.desktop"
rm -rf "$HOME/.local/share/hexapod-calculator"

# A download over HTTP cannot carry the executable bit, so a bare binary always
# arrives needing "chmod +x" or a trip through the Properties dialog.  tar does
# store the file mode, so the release asset is a tarball: the user extracts it
# (a right-click in any file manager) and the program is ready to run.
echo "      packing the release archive..."
tar --mode=0755 -czf "dist/$APP-linux.tar.gz" -C dist "$APP"

echo "      tidying up..."
rm -rf build AppDir                       # scratch; the AppImage carries everything

echo
echo "Done."
echo "  dist/$APP              run this one yourself"
echo "  dist/$APP-linux.tar.gz  upload this one to the release page"
echo
echo "Both hold the same program: portable, no Python, no installer.  The tarball"
echo "exists because a download cannot carry the executable bit, so a bare binary"
echo "would arrive needing chmod +x; extracting the tarball keeps it executable."
echo "It shows its own icon in the file manager, usually straight away; press"
echo "F5 in the folder if not.  (Only on the very first registration might the"
echo "file manager need restarting: thunar -q, nautilus -q, nemo -q.)"
echo
echo "Anyone you send it to gets the icon as well: it registers itself the"
echo "first time it runs.  './$APP --uninstall-icon' undoes that."
