#!/bin/sh
# Removes Nagenli from a Linux computer. Your library, settings and watch history stay where they are, unless you
# ask for them to go too:
#   curl -fsSL https://raw.githubusercontent.com/Quantumleapinco/nagenli-releases/master/uninstall-linux.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/Quantumleapinco/nagenli-releases/master/uninstall-linux.sh | sh -s -- --delete-data
# Your video folders are never touched: Nagenli only ever read them.
set -eu

DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nagenli"
DATA="${XDG_CONFIG_HOME:-$HOME/.config}/Nagenli"
UNITDIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT=nagenli.service

DELETE_DATA=no
for arg in "$@"; do
  case "$arg" in
    --delete-data) DELETE_DATA=yes ;;
    *) printf '%s\n' "Unknown option: $arg (the only one is --delete-data)" >&2; exit 1 ;;
  esac
done

if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$(id -u)" ]; then
  XDG_RUNTIME_DIR="/run/user/$(id -u)"
  export XDG_RUNTIME_DIR
fi
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user disable --now "$UNIT" >/dev/null 2>&1 || true
fi
rm -f "$UNITDIR/default.target.wants/$UNIT" "$UNITDIR/$UNIT"
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload || true
  systemctl --user reset-failed "$UNIT" >/dev/null 2>&1 || true
fi
rm -rf "$DIR"
printf '%s\n' "Nagenli is removed."
if [ "$DELETE_DATA" = yes ]; then
  rm -rf "$DATA"
  printf '%s\n' "Its data (library, settings, watch history) is deleted too."
else
  printf '%s\n' "Your data is still in: $DATA (delete that folder too to remove everything)."
fi
printf '%s\n' "A Nagenli you started by hand (not with the computer) keeps running until you stop it or restart the computer."
