#!/bin/bash
# setup.sh — Install/uninstall the "Open in IDE" Dolphin service menu
# Usage:
#   ./setup.sh              # Install
#   ./setup.sh --uninstall  # Remove
#   ./setup.sh --status     # Show detected IDEs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_MENU_DIR="$HOME/.local/share/kio/servicemenus"
DESKTOP_FILE="open-in-ide.desktop"
LAUNCHER_SCRIPT="open-in-ide-launcher.sh"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Detect IDEs ---
detect_ides() {
    bash "$SCRIPT_DIR/detect-ides.sh"
}

# --- Generate .desktop file ---
generate_desktop_file() {
    local ide_list="$1"

    local actions=""
    local sections=""
    local idx=0

    while IFS='|' read -r type name exec_path; do
        [ -z "$type" ] && continue
        idx=$((idx + 1))

        # Create safe action identifier
        local action_id
        action_id=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')

        # Icon mapping
        local icon=""
        case "$type" in
            vscode)
                case "$name" in
                    *Insiders*) icon="vscode-insiders" ;;
                    *)          icon="visual-studio-code" ;;
                esac
                ;;
            jetbrains)
                case "$name" in
                    *IntelliJ*)     icon="intellij-idea" ;;
                    *PyCharm*)      icon="pycharm" ;;
                    *WebStorm*)     icon="webstorm" ;;
                    *CLion*)        icon="clion" ;;
                    *GoLand*)       icon="goland" ;;
                    *PhpStorm*)     icon="phpstorm" ;;
                    *Rider*)        icon="rider" ;;
                    *RustRover*)    icon="rustrover" ;;
                    *DataGrip*)     icon="datagrip" ;;
                    *Aqua*)         icon="aqua" ;;
                    *DataSpell*)    icon="dataspell" ;;
                    *Gateway*)      icon="gateway" ;;
                    *Air*)          icon="jetbrains" ;;
                    *)              icon="jetbrains" ;;
                esac
                ;;
        esac

        # Build action section
        if [ -n "$actions" ]; then
            actions="${actions};"
        fi
        actions="${actions}${action_id}"

        sections="${sections}
[Desktop Action ${action_id}]
Name=${name}
Name[ru]=${name}
Icon=${icon}
Exec=${SERVICE_MENU_DIR}/${LAUNCHER_SCRIPT} '${exec_path}' %u
"
    done <<< "$ide_list"

    # Write .desktop file
    cat > "$SERVICE_MENU_DIR/$DESKTOP_FILE" <<DESKTOP_EOF
[Desktop Entry]
Type=Service
MimeType=all/all;inode/directory;
Actions=${actions}
X-KDE-Submenu=Открыть в IDE
X-KDE-Priority=TopLevel
${sections}
DESKTOP_EOF
}

# --- Install ---
do_install() {
    info "Detecting installed IDEs..."

    local ide_list
    ide_list=$(detect_ides)

    if [ -z "$ide_list" ]; then
        err "No supported IDEs found."
        echo ""
        echo "Supported IDEs:"
        echo "  - Visual Studio Code (+ Insiders)"
        echo "  - All JetBrains IDEs (via Toolbox or manual install):"
        echo "    IntelliJ IDEA, PyCharm, WebStorm, CLion, GoLand,"
        echo "    PhpStorm, Rider, RustRover, DataGrip, Aqua, DataSpell"
        echo ""
        echo "Install an IDE and re-run this script."
        exit 1
    fi

    local count
    count=$(echo "$ide_list" | wc -l)
    ok "Found $count IDE(s):"
    echo "$ide_list" | while IFS='|' read -r type name exec_path; do
        echo "  - $name ($type)"
    done
    echo ""

    # Create service menu directory if needed
    mkdir -p "$SERVICE_MENU_DIR"

    # Copy launcher script
    info "Installing launcher script..."
    cp "$SCRIPT_DIR/$LAUNCHER_SCRIPT" "$SERVICE_MENU_DIR/$LAUNCHER_SCRIPT"
    chmod +x "$SERVICE_MENU_DIR/$LAUNCHER_SCRIPT"
    ok "Launcher installed to $SERVICE_MENU_DIR/$LAUNCHER_SCRIPT"

    # Generate and install .desktop file
    info "Generating .desktop file..."
    generate_desktop_file "$ide_list"
    chmod +x "$SERVICE_MENU_DIR/$DESKTOP_FILE"
    ok "Service menu installed to $SERVICE_MENU_DIR/$DESKTOP_FILE"

    # Rebuild KDE service cache (non-fatal if fails)
    if command -v kbuildsycoca6 &>/dev/null; then
        info "Rebuilding KDE service cache..."
        kbuildsycoca6 --noincremental 2>/dev/null && ok "Cache rebuilt" || warn "Cache rebuild failed (Dolphin may need restart)"
    else
        warn "kbuildsycoca6 not found — restart Dolphin manually if menu doesn't appear"
    fi

    echo ""
    ok "Installation complete!"
    echo "Right-click any file or directory in Dolphin → 'Открыть в IDE'"
}

# --- Uninstall ---
do_uninstall() {
    info "Removing service menu..."

    local removed=0

    if [ -f "$SERVICE_MENU_DIR/$DESKTOP_FILE" ]; then
        rm "$SERVICE_MENU_DIR/$DESKTOP_FILE"
        ok "Removed $DESKTOP_FILE"
        removed=1
    fi

    if [ -f "$SERVICE_MENU_DIR/$LAUNCHER_SCRIPT" ]; then
        rm "$SERVICE_MENU_DIR/$LAUNCHER_SCRIPT"
        ok "Removed $LAUNCHER_SCRIPT"
        removed=1
    fi

    if [ "$removed" -eq 0 ]; then
        warn "Nothing to remove — plugin not installed"
        return
    fi

    # Rebuild KDE service cache
    if command -v kbuildsycoca6 &>/dev/null; then
        kbuildsycoca6 --noincremental 2>/dev/null || true
    fi

    ok "Uninstalled successfully"
}

# --- Status ---
do_status() {
    info "Detecting installed IDEs..."
    local ide_list
    ide_list=$(detect_ides)

    if [ -z "$ide_list" ]; then
        warn "No supported IDEs found"
    else
        echo "$ide_list" | while IFS='|' read -r type name exec_path; do
            echo "  [$type] $name → $exec_path"
        done
    fi

    echo ""
    if [ -f "$SERVICE_MENU_DIR/$DESKTOP_FILE" ]; then
        ok "Service menu: installed ($SERVICE_MENU_DIR/$DESKTOP_FILE)"
    else
        warn "Service menu: not installed"
    fi
}

# --- Main ---
case "${1:-}" in
    --uninstall|-u)
        do_uninstall
        ;;
    --status|-s)
        do_status
        ;;
    --help|-h)
        echo "Usage: ./setup.sh [OPTION]"
        echo ""
        echo "Options:"
        echo "  (no args)     Install the Dolphin service menu"
        echo "  --uninstall   Remove the service menu"
        echo "  --status      Show detected IDEs and install status"
        echo "  --help        Show this help"
        ;;
    *)
        do_install
        ;;
esac
