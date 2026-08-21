#!/bin/bash
# setup.sh — Install/uninstall the "Open in IDE" Dolphin service menu
# Usage:
#   ./setup.sh              # Install
#   ./setup.sh --uninstall  # Remove
#   ./setup.sh --status     # Show detected IDEs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_MENU_DIR="$HOME/.local/share/kio/servicemenus"
ICON_THEME_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
ICON_PREFIX="ide-dolfin"
DESKTOP_FILE="open-in-ide.desktop"
LAUNCHER_SCRIPT="open-in-ide-launcher.sh"
SHELL_MARKER_START="# ide-dolfin start"
SHELL_MARKER_END="# ide-dolfin end"

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

# --- JetBrains command name → launcher script mapping ---
declare -A JB_CMD_MAP=(
    ["IntelliJ IDEA"]="idea.sh"
    ["IntelliJ IDEA CE"]="idea.sh"
    ["PyCharm"]="pycharm.sh"
    ["PyCharm CE"]="pycharm.sh"
    ["WebStorm"]="webstorm.sh"
    ["CLion"]="clion.sh"
    ["GoLand"]="goland.sh"
    ["PhpStorm"]="phpstorm.sh"
    ["Rider"]="rider.sh"
    ["RustRover"]="rustrover.sh"
    ["DataGrip"]="datagrip.sh"
    ["Aqua"]="aqua.sh"
    ["DataSpell"]="dataspell.sh"
    ["Gateway"]="gateway.sh"
    ["JetBrains Air"]="air.sh"
)

# --- Generate shell wrapper functions ---
generate_shell_wrappers() {
    local ide_list="$1"
    local block=""

    block+="$SHELL_MARKER_START\n"

    # VS Code wrapper
    block+="ide_code() {\n"
    block+="  local bin\n"
    block+="  bin=\$(command -v code 2>/dev/null)\n"
    block+="  if [ -n \"\$bin\" ]; then\n"
    block+="    \"\$bin\" \"\$@\"\n"
    block+="  else\n"
    block+="    echo \"code: VS Code not found — install it or run setup.sh\" >&2\n"
    block+="    return 1\n"
    block+="  fi\n"
    block+="}\n"
    block+="alias code='ide_code'\n\n"

    # JetBrains wrappers
    while IFS='|' read -r type name exec_path; do
        [ -z "$type" ] && continue
        [ "$type" != "jetbrains" ] && continue

        local launcher="${JB_CMD_MAP[$name]:-}"
        [ -z "$launcher" ] && continue

        local cmd_name="${launcher%.sh}"

        block+="${cmd_name}() {\n"
        block+="  local script\n"
        block+="  script=\$(find \"\$HOME/.local/share/JetBrains/Toolbox/apps\" -path \"*/bin/${launcher}\" -type f -executable 2>/dev/null | head -1)\n"
        block+="  if [ -z \"\$script\" ]; then\n"
        block+="    script=\"${exec_path}\"\n"
        block+="  fi\n"
        block+="  if [ -n \"\$script\" ] && [ -x \"\$script\" ]; then\n"
        block+="    \"\$script\" \"\$@\"\n"
        block+="  else\n"
        block+="    echo \"${cmd_name}: not found — run setup.sh to reinstall\" >&2\n"
        block+="    return 1\n"
        block+="  fi\n"
        block+="}\n\n"
    done <<< "$ide_list"

    block+="$SHELL_MARKER_END"

    echo -e "$block"
}

# --- Install shell wrappers ---
install_shell_aliases() {
    local ide_list="$1"
    local wrappers
    wrappers=$(generate_shell_wrappers "$ide_list")

    if [ -z "$wrappers" ]; then
        return
    fi

    local files_to_update=()

    [ -f "$HOME/.bashrc" ] && files_to_update+=("$HOME/.bashrc")

    if [ -f "$HOME/.zshrc.local" ]; then
        files_to_update+=("$HOME/.zshrc.local")
    elif [ -f "$HOME/.zshrc" ]; then
        files_to_update+=("$HOME/.zshrc")
    fi

    if [ ${#files_to_update[@]} -eq 0 ]; then
        warn "No shell profile found (.bashrc / .zshrc) — skipping shell wrappers"
        return
    fi

    for profile in "${files_to_update[@]}"; do
        # Remove old block if exists (idempotent)
        remove_block_from_file "$profile"
        # Append new block
        echo "" >> "$profile"
        echo "$wrappers" >> "$profile"
        ok "Shell wrappers added to $(basename "$profile")"
    done
}

# --- Remove shell wrapper block from a file ---
remove_block_from_file() {
    local file="$1"
    [ -f "$file" ] || return

    if grep -qF "$SHELL_MARKER_START" "$file" 2>/dev/null; then
        # Use sed to remove the block between markers (inclusive)
        sed -i "/$SHELL_MARKER_START/,/$SHELL_MARKER_END/d" "$file"
        # Remove trailing blank lines that sed may leave
        sed -i -e :a -e '/^\n*$/{$d;N;ba;}' "$file"
        ok "Removed shell wrappers from $(basename "$file")"
    fi
}

# --- Remove all shell wrappers ---
remove_shell_aliases() {
    local files_to_check=()

    [ -f "$HOME/.bashrc" ] && files_to_check+=("$HOME/.bashrc")
    [ -f "$HOME/.zshrc.local" ] && files_to_check+=("$HOME/.zshrc.local")
    [ -f "$HOME/.zshrc" ] && files_to_check+=("$HOME/.zshrc")

    local removed=0
    for profile in "${files_to_check[@]}"; do
        if grep -qF "$SHELL_MARKER_START" "$profile" 2>/dev/null; then
            remove_block_from_file "$profile"
            removed=1
        fi
    done

    if [ "$removed" -eq 1 ]; then
        ok "Shell wrappers removed"
    fi
}

# --- Icon installation ---
install_icon() {
    local ide_type="$1"
    local ide_name="$2"
    local exec_path="$3"

    local icon_name=""
    local icon_source=""

    case "$ide_type" in
        vscode)
            # VS Code: use system icon if available
            if [ -f /usr/share/pixmaps/vscode.png ]; then
                icon_name="vscode"
                # Don't copy — system icon already exists
                echo "$icon_name"
                return
            fi
            # Fallback: check for icon in the project's icons/ dir
            local vs_icon="$SCRIPT_DIR/icons/vscode.svg"
            if [ -f "$vs_icon" ]; then
                icon_name="${ICON_PREFIX}-vscode"
                mkdir -p "$ICON_THEME_DIR"
                cp "$vs_icon" "$ICON_THEME_DIR/${icon_name}.svg"
                echo "$icon_name"
                return
            fi
            echo "vscode"
            return
            ;;
        jetbrains)
            # JetBrains: find icon in IDE's bin/ directory
            local ide_dir
            ide_dir=$(dirname "$(dirname "$exec_path")")

            # Try SVG first, then PNG
            for ext in svg png; do
                local candidate="$ide_dir/bin/${ide_name,,}.$ext"
                # Also try lowercase without spaces
                if [ -f "$candidate" ]; then
                    icon_name="${ICON_PREFIX}-${ide_name,,}"
                    icon_source="$candidate"
                    break
                fi
            done

            # Fallback: find any icon in bin/
            if [ -z "$icon_source" ]; then
                icon_source=$(find "$ide_dir/bin" -maxdepth 1 \( -name "*.svg" -o -name "*.png" \) 2>/dev/null | head -1)
                if [ -n "$icon_source" ]; then
                    local base
                    base=$(basename "$icon_source")
                    icon_name="${ICON_PREFIX}-${base%.*}"
                fi
            fi

            # Fallback: bundled icons
            if [ -z "$icon_source" ]; then
                local bundled="$SCRIPT_DIR/icons/${ide_name,,}.svg"
                if [ -f "$bundled" ]; then
                    icon_source="$bundled"
                    icon_name="${ICON_PREFIX}-${ide_name,,}"
                fi
            fi

            if [ -n "$icon_source" ] && [ -f "$icon_source" ]; then
                mkdir -p "$ICON_THEME_DIR"
                cp "$icon_source" "$ICON_THEME_DIR/${icon_name}.$(basename "$icon_source" | sed 's/.*\.//')"
                echo "$icon_name"
                return
            fi

            # Last resort: generic JetBrains icon
            echo "jetbrains"
            return
            ;;
    esac
}

remove_installed_icons() {
    # Remove icons we installed (prefixed with ide-dolfin-)
    find "$ICON_THEME_DIR" -name "${ICON_PREFIX}-*" -delete 2>/dev/null || true
}

# --- Generate .desktop file ---
generate_desktop_file() {
    local ide_list="$1"
    local icon_list="$2"

    local actions=""
    local sections=""

    local i=0
    while IFS='|' read -r type name exec_path; do
        [ -z "$type" ] && continue
        i=$((i + 1))

        # Create safe action identifier
        local action_id
        action_id=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')

        # Get icon name from the icon list (same order)
        local icon
        icon=$(echo "$icon_list" | sed -n "${i}p")

        # Build action section
        if [ -n "$actions" ]; then
            actions="${actions};"
        fi
        actions="${actions}${action_id}"

        sections="${sections}
[Desktop Action ${action_id}]
Name=Открыть в ${name}
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
Icon=${ICON_PREFIX}-menu
${sections}
DESKTOP_EOF
}

# --- Install menu icon ---
install_menu_icon() {
    # Try to create a combined menu icon from bundled assets
    local menu_icon="$SCRIPT_DIR/icons/menu.svg"
    if [ -f "$menu_icon" ]; then
        mkdir -p "$ICON_THEME_DIR"
        cp "$menu_icon" "$ICON_THEME_DIR/${ICON_PREFIX}-menu.svg"
        return
    fi

    # Fallback: use the first detected IDE's icon as menu icon
    local first_icon
    first_icon=$(find "$ICON_THEME_DIR" -name "${ICON_PREFIX}-*" 2>/dev/null | head -1)
    if [ -n "$first_icon" ]; then
        local ext
        ext=$(basename "$first_icon" | sed 's/.*\.//')
        cp "$first_icon" "$ICON_THEME_DIR/${ICON_PREFIX}-menu.$ext"
    fi
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

    # Create directories
    mkdir -p "$SERVICE_MENU_DIR"
    mkdir -p "$ICON_THEME_DIR"

    # Install launcher script
    info "Installing launcher script..."
    cp "$SCRIPT_DIR/$LAUNCHER_SCRIPT" "$SERVICE_MENU_DIR/$LAUNCHER_SCRIPT"
    chmod +x "$SERVICE_MENU_DIR/$LAUNCHER_SCRIPT"
    ok "Launcher installed"

    # Install icons for each IDE
    info "Installing icons..."
    local icon_list=""
    while IFS='|' read -r type name exec_path; do
        [ -z "$type" ] && continue
        local icon_name
        icon_name=$(install_icon "$type" "$name" "$exec_path")
        if [ -n "$icon_list" ]; then
            icon_list="${icon_list}
${icon_name}"
        else
            icon_list="$icon_name"
        fi
        ok "Icon for $name: $icon_name"
    done <<< "$ide_list"

    # Install menu icon
    install_menu_icon
    ok "Menu icon installed"

    # Update icon cache
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f -t "$ICON_THEME_DIR/.." 2>/dev/null || true
    fi

    # Generate and install .desktop file
    info "Generating .desktop file..."
    generate_desktop_file "$ide_list" "$icon_list"
    chmod +x "$SERVICE_MENU_DIR/$DESKTOP_FILE"
    ok "Service menu installed"

    # Rebuild KDE service cache (non-fatal if fails)
    if command -v kbuildsycoca6 &>/dev/null; then
        info "Rebuilding KDE service cache..."
        kbuildsycoca6 --noincremental 2>/dev/null && ok "Cache rebuilt" || warn "Cache rebuild failed (Dolphin may need restart)"
    else
        warn "kbuildsycoca6 not found — restart Dolphin manually if menu doesn't appear"
    fi

    # Install shell wrappers for terminal launch
    info "Installing shell wrappers..."
    install_shell_aliases "$ide_list"

    echo ""
    ok "Installation complete!"
    echo "Right-click any file or directory in Dolphin → 'Открыть в IDE'"
    echo "Terminal: use 'phpstorm .', 'idea .', 'code .' etc."
}

# --- Uninstall ---
do_uninstall() {
    info "Removing service menu..."

    # Remove shell wrappers
    remove_shell_aliases

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

    # Remove installed icons
    local icon_count
    icon_count=$(find "$ICON_THEME_DIR" -name "${ICON_PREFIX}-*" 2>/dev/null | wc -l)
    if [ "$icon_count" -gt 0 ]; then
        remove_installed_icons
        ok "Removed $icon_count icon(s)"
        removed=1
        # Update icon cache
        if command -v gtk-update-icon-cache &>/dev/null; then
            gtk-update-icon-cache -f -t "$ICON_THEME_DIR/.." 2>/dev/null || true
        fi
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

    local icon_count
    icon_count=$(find "$ICON_THEME_DIR" -name "${ICON_PREFIX}-*" 2>/dev/null | wc -l)
    if [ "$icon_count" -gt 0 ]; then
        ok "Icons: $icon_count installed"
    else
        warn "Icons: none installed"
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
