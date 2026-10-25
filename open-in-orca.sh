#!/bin/bash
# open-in-orca.sh — Open a folder/file in Orca IDE as a project
#
# Orca CLI limits (1.4.x):
#   - `repo add` only accepts git repositories (UI has kind=folder, CLI does not)
#   - AppImage args are ignored (OS open handler only takes files, not directories)
#   - Existing project can be revealed via `terminal create --focus` / `file open --focus`
#
# Usage: open-in-orca.sh <target-path> [orca-cli-or-appimage]

set -euo pipefail

TARGET="${1:-}"
ORCA_BIN="${2:-}"

TARGET="${TARGET#file://}"
if [[ "$TARGET" == *%* ]]; then
    TARGET=$(printf '%b' "${TARGET//%/\\x}" 2>/dev/null || printf '%s' "$TARGET")
fi

export DESKTOPINTEGRATION="${DESKTOPINTEGRATION:-1}"
export PATH="${HOME}/.local/bin:${HOME}/bin:/usr/local/bin:${PATH}"

# Resolve Orca CLI (never bare `orca` — that is the GNOME screen reader)
ORCA_CLI=""
for c in orca-ide "$HOME/.local/bin/orca-ide" "$HOME/.cache/orca/appimage/launcher/orca-ide"; do
    if command -v "$c" &>/dev/null || [ -x "$c" ]; then
        ORCA_CLI="$c"
        [ -x "$c" ] || ORCA_CLI=$(command -v "$c")
        break
    fi
done

# Resolve GUI binary
ORCA_GUI=""
if [ -n "$ORCA_BIN" ] && [ -x "$ORCA_BIN" ]; then
    ORCA_GUI="$ORCA_BIN"
else
    for g in "$HOME/AppImages/orca.appimage" "$HOME/AppImages/Orca.appimage"; do
        [ -x "$g" ] && ORCA_GUI="$g" && break
    done
fi

raise_orca() {
    if [ -n "$ORCA_CLI" ]; then
        if command -v setsid >/dev/null 2>&1; then
            setsid nohup "$ORCA_CLI" open >/dev/null 2>&1 &
        else
            nohup "$ORCA_CLI" open >/dev/null 2>&1 &
        fi
        disown 2>/dev/null || true
    elif [ -n "$ORCA_GUI" ]; then
        if command -v setsid >/dev/null 2>&1; then
            setsid nohup "$ORCA_GUI" >/dev/null 2>&1 &
        else
            nohup "$ORCA_GUI" >/dev/null 2>&1 &
        fi
        disown 2>/dev/null || true
    fi
}

notify() {
    local msg="$1"
    if command -v kdialog &>/dev/null; then
        kdialog --title "Orca" --passivepopup "$msg" 5 >/dev/null 2>&1 || true
    elif command -v notify-send &>/dev/null; then
        notify-send -a orca "Orca" "$msg" >/dev/null 2>&1 || true
    fi
}

# No target — just open the app
if [ -z "$TARGET" ]; then
    raise_orca
    exit 0
fi

# Make absolute
case "$TARGET" in
    /*) ;;
    *) TARGET="$(pwd)/$TARGET" ;;
esac

# Find enclosing git work tree (covers "file inside repo" and "subdir of repo")
GIT_ROOT=""
if command -v git &>/dev/null && [ -e "$TARGET" ]; then
    GIT_ROOT=$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || true)
    # git -C on a file path: use parent dir
    if [ -z "$GIT_ROOT" ] && [ -f "$TARGET" ]; then
        GIT_ROOT=$(git -C "$(dirname "$TARGET")" rev-parse --show-toplevel 2>/dev/null || true)
    fi
fi

raise_orca

if [ -z "$ORCA_CLI" ]; then
    notify "Orca CLI (orca-ide) не найден — просто открыт Orca"
    exit 0
fi

# Wait briefly for runtime
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if "$ORCA_CLI" status 2>/dev/null | grep -q 'runtimeState: ready\|runtimeReachable: true'; then
        break
    fi
    sleep 0.5
done

if [ -n "$GIT_ROOT" ]; then
    # Create project if missing, or reuse existing — then reveal it
    if ! "$ORCA_CLI" repo add --path "$GIT_ROOT" --json >/dev/null 2>&1; then
        notify "Не удалось добавить проект в Orca: $GIT_ROOT"
        exit 1
    fi

    # Reveal the worktree in the Orca window
    if [ -f "$TARGET" ]; then
        "$ORCA_CLI" file open --worktree "path:$GIT_ROOT" --path "$TARGET" --focus --json >/dev/null 2>&1 \
            || "$ORCA_CLI" terminal create --worktree "path:$GIT_ROOT" --focus --json >/dev/null 2>&1 \
            || true
    else
        # Prefer opening a terminal in the folder (reveals the workspace)
        "$ORCA_CLI" terminal create --worktree "path:$GIT_ROOT" --focus --json >/dev/null 2>&1 \
            || "$ORCA_CLI" file open --worktree "path:$GIT_ROOT" --focus --json >/dev/null 2>&1 \
            || true
    fi
    exit 0
fi

# Not a git repository — Orca CLI cannot create folder-kind projects
# (only the GUI picker can). Open Orca and tell the user.
notify "«$(basename "$TARGET")» не git-репозиторий. Orca CLI умеет открывать только git-проекты; папку без git добавьте через кнопку Add Folder в самом Orca."
exit 0
