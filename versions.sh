#!/bin/sh
# Single source of truth for versions, sourced by install.sh.
ZELLIJ_MIN=0.46          # minimum: config uses 0.46-era actions/options
ZELLIJ_TESTED=0.46.0     # version this config is known good with
FONT_NAME='Hack Nerd Font'
FONT_SIZE_MACOS=12
FONT_SIZE_LINUX=9

# Required: zellij, python3, sh
# Optional (install.sh only warns): node (OpenCode plugin), zsh (smart titles
# and TUI pins), claude / opencode (agent restore).
# Font sizes are in points; macOS renders them at 72dpi, most Linux X11
# displays at 96dpi, so Linux needs a smaller value to look the same.
# Override the per-OS size for one install with ZELLIJ_FONT_SIZE=<n>.
# Install the font via your package manager on either macOS
# (brew install --cask font-hack-nerd-font) or Linux
# (xbps-install nerd-fonts-ttf), or from:
# https://github.com/ryanoasis/nerd-fonts
