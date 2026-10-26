# Development Environment

This repository contains my personal development environment. I am using it to keep track of my configuration files and to easily set up a new system.

## Setup

To set up it to new system, run the following command:

```sh
   ./setup.sh && make
```

## Shell

Bash is the default shell. `make` adds one line to `~/.bashrc` that sources [bash/bashrc](bash/bashrc), so machine specific setup (conda, sdkman, brew ...) can stay in `~/.bashrc`.

- [Starship](https://starship.rs) prompt: [bash/starship.toml](bash/starship.toml)
- [ble.sh](https://github.com/akinomyoga/ble.sh) for fish-like autosuggestions and syntax highlighting: [bash/blerc](bash/blerc)
- fzf: `Ctrl+R` history, `Ctrl+T` files, `Alt+C` directories
- Aliases in [bash/aliases.bash](bash/aliases.bash): `ls`/`ll`/`la`/`lt` use eza, `cat` uses bat, `..`/`...`, `mkcd`, `extract`, `ports`, `myip`, `reload` ... (bypass any alias with a backslash, e.g. `\ls`)
- Snippets in `~/.config/bash/conf.d/*.bash` are sourced automatically

## Desktop

`setup.sh` also customizes the GNOME desktop (Ubuntu 24.04). Everything is configured in [desktop/desktop.conf](desktop/desktop.conf):

- Catppuccin Mocha look: Colloid GTK/Shell theme, Papirus icons with Catppuccin folders, Bibata cursor, Inter + JetBrainsMono Nerd Font
- GNOME Shell extensions: User Themes, Blur my Shell, Just Perfection, Vitals, Space Bar, Rounded Window Corners, Burn My Windows
- Auto-hiding Ubuntu Dock, Catppuccin GNOME Terminal profile, fastfetch in new terminals
- Rotating wallpapers from Wallhaven, the same image on every monitor (set `WALLPAPER_PER_MONITOR=true` for a separate, orientation matched image per monitor)

Boot and login screens (sections `plymouth`, `grub`, `gdm`, need sudo):

- Catppuccin Plymouth boot splash
- Catppuccin GRUB theme, menu visible for 10s with Windows listed (settings in `/etc/default/grub.d/99-dev-environment.cfg`)
- Catppuccin colored login screen built from Ubuntu's Yaru theme, plus Bibata cursor and Inter font
- The motherboard logo is drawn by the firmware and can only be hidden in the BIOS settings

To go back to Ubuntu's defaults:

```sh
sudo update-alternatives --remove default.plymouth /usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.plymouth && sudo update-initramfs -u
sudo rm /etc/default/grub.d/99-dev-environment.cfg && sudo update-grub
sudo update-alternatives --remove gdm-theme.gresource /usr/share/gnome-shell/theme/dev-environment/gdm-theme.gresource
```

Run it alone, or only some sections:

```sh
./desktop/setup-desktop.sh
./desktop/setup-desktop.sh wallpaper dock
```

Extension settings live in `desktop/dconf/*.ini`. After tweaking them in Extension Manager, save them back with `./desktop/setup-desktop.sh --save-dconf`.
The original GNOME settings are backed up once to `~/.local/state/dev-environment/` (restore with `dconf load /org/gnome/ < backup.ini`).

Wallpaper commands:

| Command | Shortcut | |
|---|---|---|
| `wallpaper next` | `Super+Alt+W` | Show new wallpapers |
| `wallpaper ban [all\|landscape\|portrait]` | `Super+Alt+X` | Never show the current image(s) again |
| `wallpaper fetch [N]` | | Download N new images per orientation |
| `wallpaper status` | | Current images and pool size |

Wallpapers are kept in `~/Pictures/Wallpapers/landscape` (and `portrait` in per-monitor mode). Downloaded ones are reused; only the oldest are deleted once there are more than `WALLPAPER_CACHE_MAX`, and banned ones are deleted right away. Your own images can be dropped in there too and are never deleted.
