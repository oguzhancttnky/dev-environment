#!/bin/bash
# Customizes the GNOME desktop according to desktop.conf.
# Usage:
#   ./desktop/setup-desktop.sh                  # run every enabled section
#   ./desktop/setup-desktop.sh wallpaper dock   # run only the given sections
#   ./desktop/setup-desktop.sh --save-dconf     # store current extension settings into desktop/dconf/

set -euo pipefail

DESKTOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_CACHE="$HOME/.cache/dev-environment/src"
STATE_DIR="$HOME/.local/state/dev-environment"
EXT_DCONF_ROOT="/org/gnome/shell/extensions"

# shellcheck source=desktop.conf
source "$DESKTOP_DIR/desktop.conf"

ALL_SECTIONS=(packages theme icons cursor fonts extensions dock terminal wallpaper keybindings plymouth grub gdm)

log() {
    echo "---$*---"
}

is_true() {
    [ "${1:-false}" = "true" ]
}

apt_ensure() {
    local missing=()
    for package in "$@"; do
        dpkg -s "$package" >/dev/null 2>&1 || missing+=("$package")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        sudo apt-get install -y "${missing[@]}"
    fi
}

# Clone a repo into the source cache or update it if it is already there.
git_sync() {
    local repo=$1
    local dir="$SRC_CACHE/${repo//\//-}"
    if [ -d "$dir/.git" ]; then
        git -C "$dir" pull -q --ff-only
    else
        mkdir -p "$SRC_CACHE"
        git clone -q --depth 1 "https://github.com/$repo.git" "$dir"
    fi
    echo "$dir"
}

github_latest_tag() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" | jq -r .tag_name
}

capitalize() {
    echo "$(tr '[:lower:]' '[:upper:]' <<<"${1:0:1}")${1:1}"
}

# Colloid names its themes Colloid[-Color]-Dark[-Compact][-Scheme].
colloid_theme_name() {
    local name="Colloid"
    [ "$COLLOID_COLOR" != "default" ] && name+="-$(capitalize "$COLLOID_COLOR")"
    name+="-Dark"
    [ "$COLLOID_SIZE" = "compact" ] && name+="-Compact"
    for tweak in $COLLOID_TWEAKS; do
        case "$tweak" in
            nord | dracula | gruvbox | everforest | catppuccin) name+="-$(capitalize "$tweak")" ;;
        esac
    done
    echo "$name"
}

backup_dconf() {
    mkdir -p "$STATE_DIR"
    if ! ls "$STATE_DIR"/dconf-backup-*.ini >/dev/null 2>&1; then
        local backup="$STATE_DIR/dconf-backup-$(date +%Y%m%d-%H%M%S).ini"
        dconf dump /org/gnome/ >"$backup"
        log "Backed up original GNOME settings to $backup (restore: dconf load /org/gnome/ < file)"
    fi
}

section_packages() {
    log "Installing desktop packages"
    local packages=(git curl jq pipx imagemagick sassc gnome-themes-extra gtk2-engines-murrine fontconfig)
    is_true "$ENABLE_FONTS" && packages+=(fonts-inter)
    is_true "$ENABLE_GDM" && packages+=(libglib2.0-dev-bin dbus)
    is_true "$ENABLE_GRUB" && is_true "$GRUB_SHOW_OTHER_OS" && packages+=(os-prober)
    apt_ensure "${packages[@]}"
    if is_true "$ENABLE_TERMINAL" && is_true "$TERMINAL_FASTFETCH" && ! command -v fastfetch >/dev/null; then
        sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch >/dev/null
        sudo apt-get update -y
        apt_ensure fastfetch
    fi
}

section_theme() {
    log "Installing Colloid theme ($COLLOID_COLOR, $COLLOID_TWEAKS)"
    local dir
    dir=$(git_sync vinceliuice/Colloid-gtk-theme)
    local args=(-t "$COLLOID_COLOR" -c dark -s "$COLLOID_SIZE")
    [ -n "$COLLOID_TWEAKS" ] && args+=(--tweaks $COLLOID_TWEAKS)
    is_true "$COLLOID_LIBADWAITA" && args+=(-l)
    (cd "$dir" && ./install.sh "${args[@]}" >/dev/null)

    local theme
    theme=$(colloid_theme_name)
    gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME"
    gsettings set org.gnome.desktop.interface gtk-theme "$theme"
    gsettings set org.gnome.desktop.wm.preferences theme "$theme"
    # Written even before the User Themes extension is installed; it picks the value up once enabled.
    dconf write "$EXT_DCONF_ROOT/user-theme/name" "'$theme'"
    log "Theme set to $theme"
}

section_icons() {
    log "Installing $ICON_THEME icons with $PAPIRUS_FOLDER_COLOR folders"
    local icons_dir="$HOME/.local/share/icons"
    mkdir -p "$icons_dir"
    local papirus
    papirus=$(git_sync PapirusDevelopmentTeam/papirus-icon-theme)
    for variant in Papirus Papirus-Dark Papirus-Light; do
        rm -rf "${icons_dir:?}/$variant"
        cp -r "$papirus/$variant" "$icons_dir/"
    done

    local folders
    folders=$(git_sync catppuccin/papirus-folders)
    cp -r "$folders"/src/* "$icons_dir/Papirus/"
    local switcher
    switcher=$(git_sync PapirusDevelopmentTeam/papirus-folders)
    "$switcher/papirus-folders" -C "$PAPIRUS_FOLDER_COLOR" --theme "$ICON_THEME" >/dev/null
    gtk-update-icon-cache -q -f "$icons_dir/$ICON_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"
}

section_cursor() {
    log "Installing $CURSOR_THEME cursor"
    local icons_dir="$HOME/.local/share/icons"
    if [ ! -d "$icons_dir/$CURSOR_THEME" ]; then
        local tag tmp
        tag=$(github_latest_tag ful1e5/Bibata_Cursor)
        tmp=$(mktemp -d)
        curl -fsSL "https://github.com/ful1e5/Bibata_Cursor/releases/download/$tag/$CURSOR_THEME.tar.xz" -o "$tmp/cursor.tar.xz"
        mkdir -p "$icons_dir"
        tar -xJf "$tmp/cursor.tar.xz" -C "$icons_dir"
        rm -rf "$tmp"
    fi
    gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME"
    gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE"
}

section_fonts() {
    log "Installing $NERD_FONT Nerd Font"
    local font_dir="$HOME/.local/share/fonts/${NERD_FONT}NerdFont"
    if [ ! -d "$font_dir" ]; then
        local tag tmp
        tag=$(github_latest_tag ryanoasis/nerd-fonts)
        tmp=$(mktemp -d)
        curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/$tag/$NERD_FONT.tar.xz" -o "$tmp/font.tar.xz"
        mkdir -p "$font_dir"
        tar -xJf "$tmp/font.tar.xz" -C "$font_dir"
        rm -rf "$tmp"
        fc-cache -f "$font_dir"
    fi
    gsettings set org.gnome.desktop.interface font-name "$INTERFACE_FONT"
    gsettings set org.gnome.desktop.interface document-font-name "$DOCUMENT_FONT"
    gsettings set org.gnome.desktop.interface monospace-font-name "$MONOSPACE_FONT"
}

load_extension_dconf() {
    for ini in "$DESKTOP_DIR"/dconf/*.ini; do
        [ -e "$ini" ] || continue
        dconf load "$EXT_DCONF_ROOT/$(basename "$ini" .ini)/" <"$ini"
    done
}

section_extensions() {
    log "Installing GNOME Shell extensions"
    command -v gext >/dev/null || pipx install gnome-extensions-cli
    local gext="$HOME/.local/bin/gext"
    command -v gext >/dev/null && gext=gext
    for uuid in "${EXTENSIONS[@]}"; do
        if [ -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ]; then
            echo "---$uuid is already installed---"
        else
            "$gext" -F install "$uuid"
        fi
        "$gext" -F enable "$uuid" >/dev/null
    done
    load_extension_dconf

    if [ -n "${BURN_MY_WINDOWS_EFFECTS:-}" ]; then
        local profile_dir="$HOME/.config/burn-my-windows/profiles"
        mkdir -p "$profile_dir"
        {
            echo "[burn-my-windows-profile]"
            echo "fire-enable-effect=false"
            for effect in $BURN_MY_WINDOWS_EFFECTS; do
                echo "$effect-enable-effect=true"
            done
        } >"$profile_dir/dev-environment.conf"
    fi
    log "Log out and back in for new extensions to load (Wayland)"
}

section_dock() {
    log "Configuring Ubuntu Dock"
    local schema=org.gnome.shell.extensions.dash-to-dock
    gsettings set $schema dock-position "$DOCK_POSITION"
    gsettings set $schema dash-max-icon-size "$DOCK_ICON_SIZE"
    gsettings set $schema extend-height "$DOCK_EXTEND_HEIGHT"
    if is_true "$DOCK_AUTOHIDE"; then
        gsettings set $schema dock-fixed false
        gsettings set $schema autohide true
        gsettings set $schema intellihide false
    else
        gsettings set $schema dock-fixed true
    fi
}

section_terminal() {
    log "Configuring GNOME Terminal profile '$TERMINAL_PROFILE_NAME'"
    # Fixed UUID so re-running updates the same profile instead of adding new ones.
    local uuid="c0ffee00-cafe-4dee-b0a7-ca7700cc1a55"
    local path="/org/gnome/terminal/legacy/profiles:/:$uuid/"
    dconf load "$path" <<EOF
[/]
visible-name='$TERMINAL_PROFILE_NAME'
use-theme-colors=false
use-system-font=false
font='$TERMINAL_FONT'
default-size-columns=$TERMINAL_COLUMNS
default-size-rows=$TERMINAL_ROWS
background-color='#1e1e2e'
foreground-color='#cdd6f4'
bold-color-same-as-fg=true
cursor-colors-set=true
cursor-background-color='#f5e0dc'
cursor-foreground-color='#1e1e2e'
highlight-colors-set=true
highlight-background-color='#585b70'
highlight-foreground-color='#cdd6f4'
palette=['#45475a', '#f38ba8', '#a6e3a1', '#f9e2af', '#89b4fa', '#f5c2e7', '#94e2d5', '#bac2de', '#585b70', '#f38ba8', '#a6e3a1', '#f9e2af', '#89b4fa', '#f5c2e7', '#94e2d5', '#a6adc8']
audible-bell=false
EOF
    local list
    list=$(gsettings get org.gnome.Terminal.ProfilesList list)
    if [[ "$list" != *"$uuid"* ]]; then
        gsettings set org.gnome.Terminal.ProfilesList list "${list%]*}, '$uuid']"
    fi
    gsettings set org.gnome.Terminal.ProfilesList default "$uuid"

    # Picked up by bash/bashrc, which sources ~/.config/bash/conf.d/*.bash
    local fastfetch_conf="$HOME/.config/bash/conf.d/fastfetch.bash"
    if is_true "$TERMINAL_FASTFETCH"; then
        mkdir -p "$(dirname "$fastfetch_conf")"
        cat >"$fastfetch_conf" <<'EOF'
if command -v fastfetch >/dev/null && [ "${TERM_PROGRAM:-}" != vscode ]; then
    fastfetch
fi
EOF
    else
        rm -f "$fastfetch_conf"
    fi
}

section_wallpaper() {
    log "Setting up rotating wallpapers every $WALLPAPER_INTERVAL"
    mkdir -p "$HOME/.local/bin" "$WALLPAPER_DIR/landscape" "$WALLPAPER_DIR/portrait"
    ln -sf "$DESKTOP_DIR/wallpaper.py" "$HOME/.local/bin/wallpaper"

    local unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$unit_dir"
    cat >"$unit_dir/wallpaper.service" <<EOF
[Unit]
Description=Rotate desktop wallpaper
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=$DESKTOP_DIR/wallpaper.py next
EOF
    cat >"$unit_dir/wallpaper.timer" <<EOF
[Unit]
Description=Rotate desktop wallpaper every $WALLPAPER_INTERVAL

[Timer]
OnStartupSec=1min
OnUnitActiveSec=$WALLPAPER_INTERVAL
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now wallpaper.timer
    systemctl --user start wallpaper.service || true
}

set_custom_keybinding() {
    local id=$1 name=$2 command=$3 binding=$4
    local base=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
    local path="$base/$id/"
    local schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$path"
    gsettings set "$schema" name "$name"
    gsettings set "$schema" command "$command"
    gsettings set "$schema" binding "$binding"

    local list
    list=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
    if [[ "$list" != *"$path"* ]]; then
        if [ "$list" = "@as []" ] || [ "$list" = "[]" ]; then
            list="['$path']"
        else
            list="${list%]*}, '$path']"
        fi
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$list"
    fi
}

section_keybindings() {
    log "Setting keybindings"
    set_custom_keybinding wallpaper-next "Next wallpaper" "$DESKTOP_DIR/wallpaper.py next" "$KEY_WALLPAPER_NEXT"
    set_custom_keybinding wallpaper-ban "Ban current wallpaper" "$DESKTOP_DIR/wallpaper.py ban" "$KEY_WALLPAPER_BAN"
}

section_plymouth() {
    log "Installing $PLYMOUTH_THEME boot splash"
    local dir
    dir=$(git_sync catppuccin/plymouth)
    sudo rm -rf "/usr/share/plymouth/themes/$PLYMOUTH_THEME"
    sudo cp -r "$dir/themes/$PLYMOUTH_THEME" /usr/share/plymouth/themes/
    local theme_file="/usr/share/plymouth/themes/$PLYMOUTH_THEME/$PLYMOUTH_THEME.plymouth"
    sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$theme_file" 200
    sudo update-alternatives --set default.plymouth "$theme_file"
    sudo update-initramfs -u
}

section_grub() {
    local name="catppuccin-$GRUB_FLAVOR-grub-theme"
    log "Configuring GRUB ($name, ${GRUB_MENU_TIMEOUT}s)"
    local dir
    dir=$(git_sync catppuccin/grub)
    sudo mkdir -p /usr/share/grub/themes
    sudo rm -rf "/usr/share/grub/themes/$name"
    sudo cp -r "$dir/src/$name" /usr/share/grub/themes/
    local disable_os_prober=true
    is_true "$GRUB_SHOW_OTHER_OS" && disable_os_prober=false
    # A drop-in loaded after /etc/default/grub, so the distro file stays untouched
    sudo mkdir -p /etc/default/grub.d
    sudo tee /etc/default/grub.d/99-dev-environment.cfg >/dev/null <<EOF
# Managed by dev-environment/desktop/setup-desktop.sh
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=$GRUB_MENU_TIMEOUT
GRUB_THEME="/usr/share/grub/themes/$name/theme.txt"
GRUB_DISABLE_OS_PROBER=$disable_os_prober
EOF
    sudo update-grub
}

section_gdm() {
    log "Theming the login screen (GDM)"
    # Repack Ubuntu's Yaru shell theme with recolored login screen rules as a separate
    # gdm-theme.gresource alternative; the original Yaru file is left untouched.
    local source=/usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource
    local target=/usr/share/gnome-shell/theme/dev-environment/gdm-theme.gresource
    local prefix=/org/gnome/shell/theme
    local work
    work=$(mktemp -d)
    for resource in $(gresource list "$source"); do
        local file="$work/${resource#"$prefix"/}"
        mkdir -p "$(dirname "$file")"
        gresource extract "$source" "$resource" >"$file"
    done
    cat >>"$work/gdm.css" <<EOF

/* dev-environment */
#lockDialogGroup { background-color: $GDM_BACKGROUND_COLOR; background-image: none; }
.login-dialog-button.default, .unlock-dialog .button.default { background-color: $GDM_ACCENT_COLOR; color: $GDM_BACKGROUND_COLOR; }
EOF
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo "<gresources><gresource prefix=\"$prefix\">"
        (cd "$work" && find . -type f | sed 's|^\./||' | sort | sed 's|.*|<file>&</file>|')
        echo '</gresource></gresources>'
    } >"$work.xml"
    glib-compile-resources --sourcedir="$work" --target="$work.gresource" "$work.xml"
    sudo install -D -m 0644 "$work.gresource" "$target"
    rm -rf "$work" "$work.xml" "$work.gresource"
    sudo update-alternatives --install /usr/share/gnome-shell/gdm-theme.gresource gdm-theme.gresource "$target" 50
    sudo update-alternatives --set gdm-theme.gresource "$target"

    # The login screen runs as the gdm user and reads its own settings; the cursor must be system-wide.
    if [ -d "$HOME/.local/share/icons/$CURSOR_THEME" ]; then
        sudo rm -rf "/usr/share/icons/$CURSOR_THEME"
        sudo cp -r "$HOME/.local/share/icons/$CURSOR_THEME" /usr/share/icons/
    fi
    local gdm_settings="sudo -H -u gdm dbus-run-session gsettings set org.gnome.desktop.interface"
    (cd / && $gdm_settings cursor-theme "$CURSOR_THEME" && $gdm_settings cursor-size "$CURSOR_SIZE" \
        && $gdm_settings font-name "$INTERFACE_FONT" \
        && sudo -H -u gdm dbus-run-session gsettings set org.gnome.login-screen logo "$GDM_LOGO")
    log "The new login screen shows up after the next logout or reboot"
}

save_dconf() {
    for ini in "$DESKTOP_DIR"/dconf/*.ini; do
        [ -e "$ini" ] || continue
        dconf dump "$EXT_DCONF_ROOT/$(basename "$ini" .ini)/" >"$ini"
        echo "---Saved $(basename "$ini")---"
    done
}

section_enabled() {
    case "$1" in
        packages) return 0 ;;
        theme) is_true "$ENABLE_THEME" ;;
        icons) is_true "$ENABLE_ICONS" ;;
        cursor) is_true "$ENABLE_CURSOR" ;;
        fonts) is_true "$ENABLE_FONTS" ;;
        extensions) is_true "$ENABLE_EXTENSIONS" ;;
        dock) is_true "$ENABLE_DOCK" ;;
        terminal) is_true "$ENABLE_TERMINAL" ;;
        wallpaper) is_true "$ENABLE_WALLPAPER" ;;
        keybindings) is_true "$ENABLE_KEYBINDINGS" ;;
        plymouth) is_true "$ENABLE_PLYMOUTH" ;;
        grub) is_true "$ENABLE_GRUB" ;;
        gdm) is_true "$ENABLE_GDM" ;;
        *) echo "Unknown section: $1 (available: ${ALL_SECTIONS[*]})" >&2; exit 1 ;;
    esac
}

main() {
    if [ "${1:-}" = "--save-dconf" ]; then
        save_dconf
        return
    fi
    local sections=("$@")
    [ ${#sections[@]} -eq 0 ] && sections=("${ALL_SECTIONS[@]}")

    backup_dconf
    for section in "${sections[@]}"; do
        if section_enabled "$section"; then
            "section_$section"
        else
            log "Skipping $section (disabled in desktop.conf)"
        fi
    done
    log "Desktop setup completed"
}

main "$@"
