#!/usr/bin/env bash
# Install "Ball on a String" (GNOME layer + shared engine) for the current user.
#
#   install.sh              install or update
#   install.sh --uninstall  remove the extension and the `balls` command
#                           (keeps ~/.config/ball-on-a-string.json; add --purge
#                           to delete that too)
#
# The extension directory is assembled from gnome/*.js and engine/*.js, so
# re-run this after changing any .js file, then log out and in. Tuning and
# on/off do NOT need this: `balls settings` / `balls on|off` apply live.
set -euo pipefail

UUID="ball-on-a-string@local"
OLD_UUID="ball-on-a-string@zoltan.local"   # uuid used by an earlier attempt
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"      # .../gnome
ROOT="$(cd "$HERE/.." && pwd)"                            # project root
ENGINE="$ROOT/engine"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
DEST="$EXT_DIR/$UUID"
BIN_DIR="$HOME/.local/bin"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/ball-on-a-string.json"

# enabled_list add|remove: put the uuid on / take it off GNOME's list of enabled
# extensions directly (org.gnome.shell enabled-extensions), for when the running
# shell cannot be asked. Exit status 1 if the setting is not available.
enabled_list() {
    python3 - "$UUID" "$1" <<'PY'
import ast, subprocess, sys
uuid, mode = sys.argv[1], sys.argv[2]

def read(key):
    r = subprocess.run(["gsettings", "get", "org.gnome.shell", key],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(1)
    s = r.stdout.strip()
    if s.startswith("@as"):            # an empty list prints as "@as []"
        s = s[3:].strip()
    return list(ast.literal_eval(s))   # GVariant string lists read like Python lists

def write(key, items):
    value = "[" + ", ".join("'" + x + "'" for x in items) + "]"
    r = subprocess.run(["gsettings", "set", "org.gnome.shell", key, value])
    if r.returncode != 0:
        sys.exit(1)

enabled = read("enabled-extensions")
disabled = read("disabled-extensions")
if mode == "add":
    if uuid not in enabled:
        write("enabled-extensions", enabled + [uuid])
    if uuid in disabled:
        write("disabled-extensions", [x for x in disabled if x != uuid])
else:
    if uuid in enabled:
        write("enabled-extensions", [x for x in enabled if x != uuid])
PY
}

uninstall() {   # $1 = "--purge" to remove the config file as well
    gnome-extensions disable "$UUID" 2>/dev/null || enabled_list remove 2>/dev/null || true
    for d in "$DEST" "$EXT_DIR/$OLD_UUID"; do
        if [ -L "$d" ]; then
            rm "$d";     echo "Removed $d (was a symlink; the project folder is untouched)"
        elif [ -e "$d" ]; then
            rm -rf "$d"; echo "Removed $d"
        fi
    done
    if [ -e "$BIN_DIR/balls" ]; then
        rm -f "$BIN_DIR/balls"; echo "Removed $BIN_DIR/balls"
    fi
    if [ "${1:-}" = "--purge" ]; then
        rm -f "$CONFIG" && echo "Removed $CONFIG"
    elif [ -e "$CONFIG" ]; then
        echo "Kept your settings in $CONFIG (re-run with --uninstall --purge to delete them)"
    fi
    echo "Done. The balls are gone now; GNOME forgets the extension completely at your next logout."
}

case "${1:-}" in
    --uninstall) uninstall "${2:-}"; exit 0 ;;
    "")          ;;
    *)           echo "usage: $0 [--uninstall [--purge]]" >&2; exit 1 ;;
esac

for f in "$ENGINE/physics.js" "$ENGINE/config.js" "$HERE/extension.js" \
         "$HERE/configIO.js" "$HERE/prefs.js" "$HERE/prefsWidget.js" "$HERE/metadata.json"; do
    [ -f "$f" ] || { echo "error: missing $f" >&2; exit 1; }
done

# Retire the earlier attempt so two toys never run at once.
if [ -d "$EXT_DIR/$OLD_UUID" ]; then
    gnome-extensions disable "$OLD_UUID" 2>/dev/null || true
    rm -rf "$EXT_DIR/$OLD_UUID"
    echo "Removed old install $OLD_UUID"
fi

# An earlier setup may have symlinked the extension directory to the project.
# The extension now needs files from two folders, so it must be a real
# directory: replace the link (only the link is removed, nothing it points to).
if [ -L "$DEST" ]; then
    rm "$DEST"
    echo "Replaced symlink $DEST with a real directory"
fi
mkdir -p "$DEST"
# Remove stale files from previous layouts, then copy the current set.
find "$DEST" -maxdepth 1 -type f -delete
cp "$ENGINE/physics.js" "$ENGINE/config.js" \
   "$HERE/extension.js" "$HERE/configIO.js" "$HERE/prefs.js" "$HERE/prefsWidget.js" \
   "$HERE/metadata.json" "$DEST/"
echo "Installed extension to $DEST"

mkdir -p "$BIN_DIR"
cp "$HERE/balls" "$BIN_DIR/balls"
chmod +x "$BIN_DIR/balls"
echo "Installed command to $BIN_DIR/balls"
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "  (note: $BIN_DIR is not in your PATH; zsh users: add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to ~/.zshrc)" ;;
esac

# Seed the config once; never overwrite the user's edits.
if [ ! -e "$CONFIG" ]; then
    mkdir -p "$(dirname "$CONFIG")"
    cp "$ENGINE/config.example.json" "$CONFIG"
    echo "Created $CONFIG"
fi

# Switch the extension on. GNOME keeps a list of enabled extensions (the
# org.gnome.shell enabled-extensions setting) and only runs what is on it.
# `gnome-extensions enable` asks the running shell to add us, which works on a
# re-install but fails on a first install: the shell scans the extensions
# folder only at login, so it does not know us yet. In that case put the uuid
# on the list ourselves (the same thing `gnome-extensions enable` does when no
# shell is running); the shell finds it there at the next login and starts
# the extension without anyone having to type anything.
if gnome-extensions enable "$UUID" 2>/dev/null; then
    echo "Enabled."
elif enabled_list add 2>/dev/null; then
    echo "Marked as enabled; GNOME starts it at your next login (the running GNOME had not loaded it yet)."
else
    echo "Could not mark the extension as enabled. After logging back in, run:"
    echo "    gnome-extensions enable $UUID"
fi

cat <<EOF

Code changed => log out and log back in (Wayland loads extension code only at
login). Afterwards:
    balls status       state of the extension and whether the balls are shown
    balls on | off     show / hide (hidden again after each login unless
                       "Show at login" is turned on in balls settings)
    balls settings     preferences window
    balls log          recent messages from the shell journal
EOF
