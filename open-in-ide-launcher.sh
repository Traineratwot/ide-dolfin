#!/bin/bash
# open-in-ide-launcher.sh — Lightweight launcher for IDE service menu actions
# Usage: open-in-ide-launcher.sh <ide-exec-path> <file-or-directory-url>

set -euo pipefail

IDE_EXEC="$1"
TARGET="${2:-}"

# Strip file:// URL prefix if present
TARGET="${TARGET#file://}"

# URL-decode percent-encoded characters (e.g. %20 -> space)
url_decode() {
    local url_encoded="$1"
    echo "${url_encoded//%/\\x}" | xargs -0 printf '%b' 2>/dev/null || echo "$url_encoded"
}

TARGET=$(url_decode "$TARGET")

if [ -z "$TARGET" ]; then
    # No target — just launch the IDE
    nohup "$IDE_EXEC" &>/dev/null &
elif [ -d "$TARGET" ]; then
    # Directory — open as project
    nohup "$IDE_EXEC" "$TARGET" &>/dev/null &
elif [ -f "$TARGET" ]; then
    # File — open the file (IDE decides how)
    nohup "$IDE_EXEC" "$TARGET" &>/dev/null &
else
    # Path doesn't exist, try opening anyway
    nohup "$IDE_EXEC" "$TARGET" &>/dev/null &
fi

disown
