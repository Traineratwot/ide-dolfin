#!/bin/bash
# open-in-ide-launcher.sh — Lightweight launcher for IDE service menu actions
# Usage: open-in-ide-launcher.sh <ide-exec-path-or-command> [file-or-directory-url]

set -euo pipefail

IDE_EXEC="${1:-}"
TARGET="${2:-}"

if [ -z "$IDE_EXEC" ]; then
    echo "open-in-ide-launcher: missing IDE exec path" >&2
    exit 1
fi

# Strip file:// URL prefix if present
TARGET="${TARGET#file://}"

# URL-decode percent-encoded characters (e.g. %20 -> space)
url_decode() {
    local url_encoded="$1"
    if [[ "$url_encoded" != *%* ]]; then
        printf '%s' "$url_encoded"
        return
    fi
    printf '%b' "${url_encoded//%/\\x}" 2>/dev/null || printf '%s' "$url_encoded"
}

if [ -n "$TARGET" ]; then
    TARGET=$(url_decode "$TARGET")
fi

# AppImage desktop integration (Orca and other AppImages)
export DESKTOPINTEGRATION="${DESKTOPINTEGRATION:-1}"

# Make sure user-local bins resolve when launched from Dolphin
export PATH="${HOME}/.local/bin:${HOME}/bin:/usr/local/bin:${PATH}"

# Support both a single executable path and a multi-word command
# (e.g. "flatpak run com.visualstudio.code").
read -r -a IDE_CMD <<<"$IDE_EXEC"

# New session + nohup: IDE survives terminal / Dolphin close
if command -v setsid >/dev/null 2>&1; then
    if [ -n "$TARGET" ]; then
        setsid nohup "${IDE_CMD[@]}" "$TARGET" >/dev/null 2>&1 &
    else
        setsid nohup "${IDE_CMD[@]}" >/dev/null 2>&1 &
    fi
else
    if [ -n "$TARGET" ]; then
        nohup "${IDE_CMD[@]}" "$TARGET" >/dev/null 2>&1 &
    else
        nohup "${IDE_CMD[@]}" >/dev/null 2>&1 &
    fi
fi

disown 2>/dev/null || true
exit 0
