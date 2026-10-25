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
# Launches IDEs detached from the terminal (like a desktop shortcut):
# closing the terminal window must not kill the IDE.
generate_shell_wrappers() {
    local ide_list="$1"
    local block=""

    block+="$SHELL_MARKER_START\n"

    # Shared launcher: run in background, drop controlling tty, ignore SIGHUP
    block+="_ide_detach() {\n"
    block+="  # new session + nohup + redirected stdio: survives terminal close\n"
    block+="  if command -v setsid >/dev/null 2>&1; then\n"
    block+="    setsid nohup \"\$@\" >/dev/null 2>&1 &\n"
    block+="  else\n"
    block+="    nohup \"\$@\" >/dev/null 2>&1 &\n"
    block+="  fi\n"
    block+="  disown 2>/dev/null || true\n"
    block+="  return 0\n"
    block+="}\n\n"

    # VS Code wrapper
    block+="ide_code() {\n"
    block+="  local bin\n"
    block+="  bin=\$(command -v code 2>/dev/null)\n"
    block+="  if [ -n \"\$bin\" ]; then\n"
    block+="    _ide_detach \"\$bin\" \"\$@\"\n"
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
        block+="    _ide_detach \"\$script\" \"\$@\"\n"
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
        orca)
            # Orca IDE (AppImage) — use its own icon when present
            local orca_icon=""
            for candidate in \
                "$HOME/AppImages/.icons/orca" \
                "$HOME/AppImages/.icons/orca.png" \
                "$SCRIPT_DIR/icons/orca.png" \
                "$SCRIPT_DIR/icons/orca.svg"
            do
                if [ -f "$candidate" ]; then
                    orca_icon="$candidate"
                    break
                fi
            done

            if [ -n "$orca_icon" ]; then
                icon_name="${ICON_PREFIX}-orca"
                mkdir -p "$ICON_THEME_DIR"
                local ext
                ext=$(basename "$orca_icon" | sed 's/.*\.//')
                # Extension-less AppImage icons are PNG
                case "$ext" in
                    svg|png|xpm) ;;
                    *) ext="png" ;;
                esac
                cp "$orca_icon" "$ICON_THEME_DIR/${icon_name}.$ext"
                echo "$icon_name"
                return
            fi
            echo "orca"
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

# Escape a value for use as a single double-quoted argument in Exec=
desktop_exec_quote() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# KF 6.29.x regression: service menus that set X-KDE-Submenu are silently
# ignored in Dolphin (KDE bugs 524239 / 524533). Fixed in KF 6.30 and in
# Arch's kio 6.29.0-2.
has_broken_submenu_support() {
    local ver=""
    if command -v kbuildsycoca6 &>/dev/null; then
        ver=$(kbuildsycoca6 --version 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)
    fi
    if [ -z "$ver" ] && command -v kf6-config &>/dev/null; then
        ver=$(kf6-config --version 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)
    fi
    [ -z "$ver" ] && return 1

    local major minor
    major="${ver%%.*}"
    minor="${ver#*.}"
    minor="${minor%%.*}"
    # 6.29.* is the broken range
    [ "$major" -eq 6 ] && [ "$minor" -eq 29 ]
}

# Menu styles:
#   submenu — named "Открыть в IDE" via X-KDE-Submenu (needs KF != 6.29)
#   actions — no TopLevel / no Submenu → Dolphin's built-in "Действия" submenu
#   picker  — one "Открыть в IDE..." item + kdialog --menu
#   flat    — items at the top level of the context menu
MENU_STYLE="${MENU_STYLE:-auto}"

resolve_menu_style() {
    local style="$1"
    if [ "$style" != "auto" ] && [ -n "$style" ]; then
        echo "$style"
        return
    fi
    if has_broken_submenu_support; then
        # True submenu without the broken key: drop TopLevel so Dolphin
        # groups the items under its own "Действия" menu.
        echo "actions"
    else
        echo "submenu"
    fi
}

# Generate a one-shot picker that lists the detected IDEs (used for menu-style=picker)
generate_picker_script() {
    local ide_list="$1"
    local dest="$SERVICE_MENU_DIR/open-in-ide-picker.sh"

    {
        cat <<'PICKER_HEAD'
#!/bin/bash
# open-in-ide-picker.sh — choose an IDE and open the target path
set -euo pipefail
TARGET="${1:-}"
TARGET="${TARGET#file://}"
if [[ "$TARGET" == *%* ]]; then
    TARGET=$(printf '%b' "${TARGET//%/\\x}" 2>/dev/null || printf '%s' "$TARGET")
fi
export DESKTOPINTEGRATION="${DESKTOPINTEGRATION:-1}"
export PATH="${HOME}/.local/bin:${HOME}/bin:/usr/local/bin:${PATH}"

declare -a NAMES=()
declare -a EXECS=()
PICKER_HEAD

        while IFS='|' read -r type name exec_path; do
            [ -z "$type" ] && continue
            # Orca: project-aware wrapper
            if [ "$type" = "orca" ]; then
                exec_path="$SERVICE_MENU_DIR/open-in-orca.sh"
            fi
            # Escape for single-quoted bash strings
            local en ee
            en=$(printf '%s' "$name" | sed "s/'/'\\\\''/g")
            ee=$(printf '%s' "$exec_path" | sed "s/'/'\\\\''/g")
            echo "NAMES+=('$en')"
            echo "EXECS+=('$ee')"
        done <<< "$ide_list"

        cat <<'PICKER_TAIL'

if [ "${#NAMES[@]}" -eq 0 ]; then
    echo "No IDEs detected — re-run setup.sh" >&2
    exit 1
fi

choice=""
if [ "${#NAMES[@]}" -eq 1 ]; then
    choice="${NAMES[0]}"
elif command -v kdialog &>/dev/null; then
    args=(--title "Открыть в IDE" --menu "Выберите IDE")
    for i in "${!NAMES[@]}"; do
        args+=("${NAMES[$i]}" "${NAMES[$i]}")
    done
    choice=$(kdialog "${args[@]}" 2>/dev/null || true)
elif command -v zenity &>/dev/null; then
    choice=$(zenity --list --title="Открыть в IDE" \
        --column="IDE" "${NAMES[@]}" 2>/dev/null || true)
else
    # Fallback: first IDE
    choice="${NAMES[0]}"
fi

[ -z "$choice" ] && exit 0

for i in "${!NAMES[@]}"; do
    if [ "${NAMES[$i]}" = "$choice" ]; then
        exec_path="${EXECS[$i]}"
        read -r -a cmd <<<"$exec_path"
        if command -v setsid >/dev/null 2>&1; then
            if [ -n "$TARGET" ]; then
                setsid nohup "${cmd[@]}" "$TARGET" >/dev/null 2>&1 &
            else
                setsid nohup "${cmd[@]}" >/dev/null 2>&1 &
            fi
        else
            if [ -n "$TARGET" ]; then
                nohup "${cmd[@]}" "$TARGET" >/dev/null 2>&1 &
            else
                nohup "${cmd[@]}" >/dev/null 2>&1 &
            fi
        fi
        disown 2>/dev/null || true
        exit 0
    fi
done
exit 1
PICKER_TAIL
    } > "$dest"
    chmod +x "$dest"
}

# --- Generate .desktop file ---
generate_desktop_file() {
    local ide_list="$1"
    local icon_list="$2"
    local style
    style=$(resolve_menu_style "$MENU_STYLE")

    local actions=""
    local sections=""
    local submenu_line=""
    local priority_line=""

    if [ "$style" = "picker" ]; then
        generate_picker_script "$ide_list"
        local quoted_picker
        quoted_picker=$(desktop_exec_quote "$SERVICE_MENU_DIR/open-in-ide-picker.sh")
        actions="pick-ide;"
        submenu_line="X-KDE-Submenu=Открыть в IDE"
        priority_line="X-KDE-Priority=TopLevel"
        if has_broken_submenu_support; then
            submenu_line="#X-KDE-Submenu=Открыть в IDE"
        fi
        sections="
[Desktop Action pick-ide]
Name=Открыть в IDE...
Icon=${ICON_PREFIX}-menu
Exec=${quoted_picker} %u
"
    else
        local i=0
        while IFS='|' read -r type name exec_path; do
            [ -z "$type" ] && continue
            i=$((i + 1))

            local action_id
            action_id=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')

            local icon
            icon=$(echo "$icon_list" | sed -n "${i}p")

            # Trailing semicolon is required by the Desktop Entry list syntax.
            actions="${actions}${action_id};"

            local quoted_exec
            quoted_exec=$(desktop_exec_quote "$exec_path")

            # Orca: use project-aware wrapper (AppImage ignores path args)
            if [ "$type" = "orca" ]; then
                quoted_exec=$(desktop_exec_quote "$SERVICE_MENU_DIR/open-in-orca.sh")
            fi

            sections="${sections}
[Desktop Action ${action_id}]
Name=Открыть в ${name}
Icon=${icon}
Exec=${SERVICE_MENU_DIR}/${LAUNCHER_SCRIPT} \"${quoted_exec}\" %u
"
        done <<< "$ide_list"

        case "$style" in
            submenu)
                submenu_line="X-KDE-Submenu=Открыть в IDE"
                priority_line="X-KDE-Priority=TopLevel"
                ;;
            actions)
                # No X-KDE-Submenu (broken on KF 6.29) and no TopLevel:
                # Dolphin/KIO groups these under its built-in "Действия" menu.
                submenu_line="#X-KDE-Submenu=Открыть в IDE"
                priority_line="#X-KDE-Priority=TopLevel"
                ;;
            flat|*)
                submenu_line="#X-KDE-Submenu=Открыть в IDE"
                priority_line="X-KDE-Priority=TopLevel"
                ;;
        esac
    fi

    info "Menu style: $style"

    cat > "$SERVICE_MENU_DIR/$DESKTOP_FILE" <<DESKTOP_EOF
[Desktop Entry]
Type=Service
Name=Открыть в IDE
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
MimeType=inode/directory;application/octet-stream;all/allfiles;all/all;
Actions=${actions}
${submenu_line}
${priority_line}
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
        echo "  - Orca IDE (AppImage / orca-ide)"
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

    # Orca needs a project-aware wrapper (AppImage args are ignored)
    if echo "$ide_list" | grep -q '^orca|'; then
        cp "$SCRIPT_DIR/open-in-orca.sh" "$SERVICE_MENU_DIR/open-in-orca.sh"
        chmod +x "$SERVICE_MENU_DIR/open-in-orca.sh"
        ok "Orca project launcher installed"
    fi

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

    # Validate .desktop syntax (non-fatal)
    if command -v desktop-file-validate &>/dev/null; then
        if desktop-file-validate "$SERVICE_MENU_DIR/$DESKTOP_FILE" 2>&1; then
            ok "Service menu validates"
        else
            warn "desktop-file-validate reported issues (menu may still work)"
        fi
    fi

    # Rebuild KDE service cache (non-fatal if fails)
    if command -v kbuildsycoca6 &>/dev/null; then
        info "Rebuilding KDE service cache..."
        kbuildsycoca6 --noincremental 2>/dev/null && ok "Cache rebuilt" || warn "Cache rebuild failed (Dolphin may need restart)"
    elif command -v kbuildsycoca5 &>/dev/null; then
        info "Rebuilding KDE service cache..."
        kbuildsycoca5 --noincremental 2>/dev/null && ok "Cache rebuilt" || warn "Cache rebuild failed (Dolphin may need restart)"
    else
        warn "kbuildsycoca6 not found — restart Dolphin manually if menu doesn't appear"
    fi

    # Install shell wrappers for terminal launch
    info "Installing shell wrappers..."
    install_shell_aliases "$ide_list"

    echo ""
    ok "Installation complete!"
    local style
    style=$(resolve_menu_style "$MENU_STYLE")
    case "$style" in
        submenu)
            echo "Dolphin: ПКМ → «Открыть в IDE» → нужный IDE"
            ;;
        actions)
            echo "Dolphin: ПКМ → «Действия» → «Открыть в …» (встроенное подменю)"
            echo "  (именованное подменю «Открыть в IDE» вернётся после KF ≥ 6.30)"
            ;;
        picker)
            echo "Dolphin: ПКМ → «Открыть в IDE...» → выбор IDE в диалоге"
            ;;
        *)
            echo "Dolphin: ПКМ → «Открыть в PhpStorm» / «Открыть в Orca» / …"
            ;;
    esac
    echo "Terminal: use 'phpstorm .', 'idea .', 'code .' etc."
    echo ""
    echo "Menu style override: ./setup.sh --menu-style=submenu|actions|picker|flat"
    echo "Restart Dolphin (close all windows and open again) to pick up the menu."
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

    if [ -f "$SERVICE_MENU_DIR/open-in-ide-picker.sh" ]; then
        rm "$SERVICE_MENU_DIR/open-in-ide-picker.sh"
        ok "Removed open-in-ide-picker.sh"
        removed=1
    fi

    if [ -f "$SERVICE_MENU_DIR/open-in-orca.sh" ]; then
        rm "$SERVICE_MENU_DIR/open-in-orca.sh"
        ok "Removed open-in-orca.sh"
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
    info "Menu style: $(resolve_menu_style "$MENU_STYLE") (auto-resolved: $(resolve_menu_style auto))"
    if has_broken_submenu_support; then
        warn "KF 6.29 X-KDE-Submenu regression is active on this system"
    fi

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
while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall|-u)
            do_uninstall
            exit 0
            ;;
        --status|-s)
            do_status
            exit 0
            ;;
        --menu-style=*)
            MENU_STYLE="${1#--menu-style=}"
            case "$MENU_STYLE" in
                submenu|actions|picker|flat|auto) ;;
                *)
                    err "Unknown menu style: $MENU_STYLE"
                    echo "Valid: submenu, actions, picker, flat, auto"
                    exit 1
                    ;;
            esac
            shift
            ;;
        --menu-style)
            shift
            MENU_STYLE="${1:-auto}"
            case "$MENU_STYLE" in
                submenu|actions|picker|flat|auto) ;;
                *)
                    err "Unknown menu style: $MENU_STYLE"
                    echo "Valid: submenu, actions, picker, flat, auto"
                    exit 1
                    ;;
            esac
            shift
            ;;
        --help|-h)
            echo "Usage: ./setup.sh [OPTION]"
            echo ""
            echo "Options:"
            echo "  (no args)              Install the Dolphin service menu"
            echo "  --uninstall            Remove the service menu"
            echo "  --status               Show detected IDEs and install status"
            echo "  --menu-style=STYLE     How items are shown in the context menu:"
            echo "      auto     (default) submenu on KF >= 6.30, actions on KF 6.29"
            echo "      submenu  named \"Открыть в IDE\" (broken on KF 6.29)"
            echo "      actions  Dolphin's built-in \"Действия\" submenu"
            echo "      picker   one item + kdialog/zenity to choose an IDE"
            echo "      flat     items at the top level of the context menu"
            echo "  --help                 Show this help"
            exit 0
            ;;
        *)
            err "Unknown option: $1"
            echo "Try ./setup.sh --help"
            exit 1
            ;;
    esac
done

do_install
