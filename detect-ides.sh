#!/bin/bash
# detect-ides.sh — Detect installed IDEs on the system
# Output format: TYPE|NAME|EXEC_PATH (one per line)
# Types: vscode, jetbrains

set -euo pipefail

# --- VS Code ---
find_vscode() {
    local paths=(
        "code"
        "/usr/bin/code"
        "/snap/bin/code"
        "/usr/local/bin/code"
    )
    for p in "${paths[@]}"; do
        if command -v "$p" &>/dev/null || [ -x "$p" ]; then
            echo "vscode|Visual Studio Code|$p"
            return
        fi
    done

    # Flatpak
    if command -v flatpak &>/dev/null; then
        if flatpak list --app 2>/dev/null | grep -qi "code"; then
            echo "vscode|Visual Studio Code|flatpak run com.visualstudio.code"
            return
        fi
    fi

    # Code Insiders
    for p in "code-insiders" "/usr/bin/code-insiders" "/snap/bin/code-insiders"; do
        if command -v "$p" &>/dev/null || [ -x "$p" ]; then
            echo "vscode|Visual Studio Code Insiders|$p"
            return
        fi
    done
}

# --- JetBrains IDEs ---
# Maps directory name (both cases) -> display name
declare -A JB_IDE_MAP=(
    ["IntelliJ IDEA"]="IntelliJ IDEA"
    ["IntelliJ IDEA CE"]="IntelliJ IDEA CE"
    ["intellij-idea"]="IntelliJ IDEA"
    ["intellij-idea-ce"]="IntelliJ IDEA CE"
    ["PyCharm"]="PyCharm"
    ["PyCharm CE"]="PyCharm CE"
    ["pycharm"]="PyCharm"
    ["pycharm-ce"]="PyCharm CE"
    ["WebStorm"]="WebStorm"
    ["webstorm"]="WebStorm"
    ["CLion"]="CLion"
    ["clion"]="CLion"
    ["GoLand"]="GoLand"
    ["goland"]="GoLand"
    ["PhpStorm"]="PhpStorm"
    ["phpstorm"]="PhpStorm"
    ["Rider"]="Rider"
    ["rider"]="Rider"
    ["RustRover"]="RustRover"
    ["rustrover"]="RustRover"
    ["DataGrip"]="DataGrip"
    ["datagrip"]="DataGrip"
    ["Aqua"]="Aqua"
    ["aqua"]="Aqua"
    ["DataSpell"]="DataSpell"
    ["dataspell"]="DataSpell"
    ["Gateway"]="Gateway"
    ["gateway"]="Gateway"
    ["Air"]="JetBrains Air"
    ["air"]="JetBrains Air"
)

# Launcher script name per IDE type
declare -A JB_LAUNCHER=(
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

find_jetbrains_toolbox() {
    local toolbox_dir="$HOME/.local/share/JetBrains/Toolbox"
    [ -d "$toolbox_dir" ] || return

    for ide_dir in "$toolbox_dir"/apps/*/; do
        [ -d "$ide_dir" ] || continue
        local ide_name
        ide_name=$(basename "$ide_dir")

        local display_name="${JB_IDE_MAP[$ide_name]:-}"
        [ -z "$display_name" ] && continue

        local launcher="${JB_LAUNCHER[$display_name]:-}"
        [ -z "$launcher" ] && continue

        local script=""
        # Try ch-0 structure (old Toolbox)
        local ch0="$ide_dir/ch-0"
        if [ -d "$ch0" ]; then
            script=$(find "$ch0" -maxdepth 3 -name "$launcher" -path "*/bin/*" 2>/dev/null | head -1)
        fi
        # Try direct structure (new Toolbox)
        if [ -z "$script" ] && [ -d "$ide_dir/bin" ]; then
            local candidate="$ide_dir/bin/$launcher"
            [ -x "$candidate" ] && script="$candidate"
        fi
        # Fallback: find any .sh in bin/ that looks like a launcher
        if [ -z "$script" ] && [ -d "$ide_dir/bin" ]; then
            script=$(find "$ide_dir/bin" -maxdepth 1 -name "*.sh" -executable 2>/dev/null | head -1)
        fi

        [ -n "$script" ] && echo "jetbrains|$display_name|$(realpath "$script")"
    done
}

find_jetbrains_manual() {
    local -a search_dirs=(
        "/opt"
        "$HOME/.local/share"
        "$HOME"
    )

    for dir in "${search_dirs[@]}"; do
        [ -d "$dir" ] || continue
        for pattern in "intellij-idea*" "idea-*" "pycharm*" "webstorm*" "clion*" "goland*" "phpstorm*" "rider*" "rustrover*" "datagrip*" "aqua*" "dataspell*"; do
            for ide_path in "$dir"/$pattern/; do
                [ -d "$ide_path" ] || continue
                local bin_dir="$ide_path/bin"
                [ -d "$bin_dir" ] || continue

                for launcher in "$bin_dir"/*.sh; do
                    [ -x "$launcher" ] || continue
                    local base
                    base=$(basename "$launcher" .sh)
                    local display_name
                    case "$base" in
                        idea)       display_name="IntelliJ IDEA" ;;
                        pycharm)    display_name="PyCharm" ;;
                        webstorm)   display_name="WebStorm" ;;
                        clion)      display_name="CLion" ;;
                        goland)     display_name="GoLand" ;;
                        phpstorm)   display_name="PhpStorm" ;;
                        rider)      display_name="Rider" ;;
                        rustrover)  display_name="RustRover" ;;
                        datagrip)   display_name="DataGrip" ;;
                        aqua)       display_name="Aqua" ;;
                        dataspell)  display_name="DataSpell" ;;
                        gateway)    display_name="Gateway" ;;
                        *)          display_name="$base" ;;
                    esac
                    echo "jetbrains|$display_name|$(realpath "$launcher")"
                    break 2  # Found launcher for this ide_path, move to next pattern
                done
            done
        done
    done
}

# --- Main ---
{
    find_vscode
    find_jetbrains_toolbox
    find_jetbrains_manual
} | sort -u -t'|' -k2,2 | sed 's|//+|/|g'
