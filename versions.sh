#!/bin/sh
# Single source of truth for versions, sourced by install.sh.
ZELLIJ_MIN=0.46          # minimum: config uses 0.46-era actions/options
ZELLIJ_TESTED=0.46.0     # version this config is known good with
FONT_NAME='Hack Nerd Font'

# Required: zellij, python3, sh
# Optional (install.sh only warns): node (OpenCode plugin), zsh (smart titles
# and TUI pins), claude / opencode (agent restore).
# Install the font via your package manager on either macOS or Linux
# (e.g. brew install --cask font-hack-nerd-font), or from:
# https://github.com/ryanoasis/nerd-fonts
