#!/bin/sh
# Installs Nagenli on a Linux computer (64-bit Intel/AMD or ARM), or repairs/upgrades an existing install. Run it,
# as the person who is to own Nagenli (not with sudo), with:
#   curl -fsSL https://raw.githubusercontent.com/Quantumleapinco/nagenli-releases/master/install-linux.sh | sh
# It puts Nagenli in ~/.local/share/nagenli/bin, makes it start with the computer (a systemd user unit) and starts it.
# Nagenli updates itself from then on, and fetches its own ffmpeg. Nothing here needs an administrator password; the
# one step that may (starting at boot before anyone logs in) is said at the end, with the command for it.
set -eu

FEED=https://raw.githubusercontent.com/Quantumleapinco/nagenli-releases/master
DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nagenli/bin"
DATA="${XDG_CONFIG_HOME:-$HOME/.config}/Nagenli"
UNITDIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT=nagenli.service
PORT=8686
URL="http://127.0.0.1:$PORT"

say() { printf '%s\n' "$*"; }
fail() { printf '%s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
  Linux) ;;
  *) fail "This installer is for Linux. On a Mac use install-mac.sh, on Windows Nagenli-Setup.exe." ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  armv7l | armv6l | armhf) fail "This computer runs a 32-bit system ($(uname -m)). Nagenli needs a 64-bit one: on a Raspberry Pi, the 64-bit Raspberry Pi OS." ;;
  *) fail "This computer's processor ($(uname -m)) is not supported." ;;
esac

# Downloads: curl, or wget where there is no curl.
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL "$1" -o "$2"; }
  answers() { curl -s -o /dev/null --max-time 2 "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -q -O "$2" "$1"; }
  answers() { wget -q -O /dev/null --timeout=2 --tries=1 "$1"; }
else
  fail "Neither curl nor wget is on this computer. Install one (for example: sudo apt install curl) and run this again."
fi
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  fail "sha256sum is not on this computer (it is part of coreutils). Install it and run this again."
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

say "Downloading Nagenli..."
fetch "$FEED/manifest.json" "$TMP/manifest.json" || fail "Could not reach the releases. Check the internet connection and try again."
fetch "$FEED/nagenli-linux-$ARCH" "$TMP/nagenli" || fail "This release has no Nagenli for Linux ($ARCH) yet."

# The manifest lists each file with its sha256; take the one of our file.
WANT="$(tr -d '\n' < "$TMP/manifest.json" \
  | grep -oE "\"nagenli-linux-$ARCH\" *: *\{[^}]*\}" \
  | grep -oE '"sha256" *: *"[0-9a-f]{64}"' \
  | grep -oE '[0-9a-f]{64}' | head -n 1 || true)"
if [ -z "$WANT" ]; then
  fail "This release has no Nagenli for Linux ($ARCH) yet."
fi
GOT="$(sha256 "$TMP/nagenli")"
if [ "$WANT" != "$GOT" ]; then
  fail "The download is damaged (its fingerprint does not match the release). Try again."
fi

# Put the new program in place. A Nagenli that is running keeps running from the file it started with.
mkdir -p "$DIR"
chmod 700 "$DIR/.." 2>/dev/null || true
cp "$TMP/nagenli" "$DIR/nagenli.new"
chmod 755 "$DIR/nagenli.new"
mv -f "$DIR/nagenli.new" "$DIR/nagenli"

# ffmpeg: Nagenli fetches its own tested build (9.1) by itself in its first minutes, and prefers a recent ffmpeg of
# this system's own (which may use the graphics card). That build needs glibc 2.35 or newer; say so where it cannot run.
HAVE_FF=no
if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then HAVE_FF=yes; fi
GLIBC="$(getconf GNU_LIBC_VERSION 2>/dev/null | cut -d' ' -f2 || true)"
GLIBC_OK=no
case "$GLIBC" in
  2.*) [ "${GLIBC#2.}" -ge 35 ] 2>/dev/null && GLIBC_OK=yes ;;
esac
FF_NOTE=""
if [ "$HAVE_FF" = no ] && [ "$GLIBC_OK" = no ]; then
  FF_NOTE="ffmpeg is missing, and the one Nagenli brings cannot run on this system (it needs glibc 2.35 or newer${GLIBC:+; this one has $GLIBC}). Videos will not play until you install ffmpeg: sudo apt install ffmpeg, sudo dnf install ffmpeg, or sudo apk add ffmpeg. Then restart Nagenli."
fi

# Start with the computer: a systemd user unit. Keep this text the same as unitText in internal/server/unit.go.
if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$(id -u)" ]; then
  XDG_RUNTIME_DIR="/run/user/$(id -u)"
  export XDG_RUNTIME_DIR
fi
SYSTEMD=no
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  SYSTEMD=yes
fi
EXEC="$(printf '%s' "$DIR/nagenli" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/%/%%/g' -e 's/\$/$$/g')"
WROTE_UNIT=no
if [ -d /run/systemd/system ]; then
  mkdir -p "$UNITDIR"
  cat > "$UNITDIR/$UNIT" <<UNITEOF
[Unit]
Description=Nagenli media server
StartLimitIntervalSec=600
StartLimitBurst=10

[Service]
Type=simple
ExecStart="$EXEC" -no-browser
Environment=NAGENLI_SERVICE=systemd
Restart=on-failure
RestartSec=3
SuccessExitStatus=75
RestartForceExitStatus=75
TimeoutStopSec=20
NoNewPrivileges=yes
UMask=0077
StandardOutput=null
StandardError=null

[Install]
WantedBy=default.target
UNITEOF
  WROTE_UNIT=yes
fi

say "Starting Nagenli..."
if [ "$SYSTEMD" = yes ]; then
  systemctl --user daemon-reload
  systemctl --user enable "$UNIT" >/dev/null 2>&1
  systemctl --user restart "$UNIT"
else
  if answers "$URL"; then
    say "Nagenli is already running here. It now updates itself to this version, or restart it to use it at once."
  else
    nohup "$DIR/nagenli" -no-browser >/dev/null 2>&1 &
  fi
fi
UP=no
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  if answers "$URL"; then UP=yes; break; fi
  sleep 1
done
if [ "$UP" = no ]; then
  fail "Nagenli did not start. Its log is in $DATA/nagenli.log"
fi
NAGENLI="$DIR/nagenli"
ASK="-addr 127.0.0.1:$PORT"

# A new install with someone at a terminal: ask where the videos are. Never without a terminal (the script is usually
# piped from curl, so the answers are read from /dev/tty), and never when Nagenli already has folders.
TTY=no
if [ -r /dev/tty ] && ( : </dev/tty ) 2>/dev/null; then TTY=yes; fi
# askdir QUESTION: prints a folder that exists and can be read, or nothing (Enter skips).
askdir() {
  for _ in 1 2 3; do
    printf '%s ' "$1" >/dev/tty
    ANSWER=""
    IFS= read -r ANSWER </dev/tty || ANSWER=""
    case "$ANSWER" in
      "") return 0 ;;
      "~") ANSWER="$HOME" ;;
      "~/"*) ANSWER="$HOME/${ANSWER#\~/}" ;;
    esac
    if [ ! -e "$ANSWER" ]; then
      say "There is no folder $ANSWER on this computer." >/dev/tty
    elif [ ! -d "$ANSWER" ]; then
      say "$ANSWER is a file, not a folder." >/dev/tty
    elif [ ! -r "$ANSWER" ] || [ ! -x "$ANSWER" ]; then
      say "$(id -un) cannot read $ANSWER. Give it read access (for example: chmod -R o+rX, or add $(id -un) to the folder's group), or choose another." >/dev/tty
    else
      printf '%s' "$ANSWER"
      return 0
    fi
  done
  say "Skipped. Folders can be added later in Settings." >/dev/tty
}
HAS=0
# shellcheck disable=SC2086
"$NAGENLI" -has-folders $ASK >/dev/null 2>&1 || HAS=$?
if [ "$TTY" = yes ] && [ "$HAS" = 3 ]; then
  say ""
  FILMS="$(askdir "Where are your films? (a folder; Enter to skip)")"
  SHOWS="$(askdir "Where are your shows? (Enter to skip)")"
  set --
  [ -n "$FILMS" ] && set -- "$@" -add-folder "$FILMS"
  [ -n "$SHOWS" ] && set -- "$@" -add-folder "$SHOWS"
  if [ $# -gt 0 ]; then
    # shellcheck disable=SC2086
    "$NAGENLI" "$@" $ASK || say "Those folders can be added later in Settings."
  fi
fi

say ""
say "Nagenli is running."
ADDRS="$(hostname -I 2>/dev/null || true)"
if [ -z "$ADDRS" ] && command -v ip >/dev/null 2>&1; then
  ADDRS="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ')"
fi
SHOWN=no
for A in $ADDRS; do
  case "$A" in
    10.* | 192.168.* | 172.1[6-9].* | 172.2[0-9].* | 172.3[01].* | 100.*)
      if [ "$SHOWN" = no ]; then say "Open it from a phone, TV or another computer at home:"; SHOWN=yes; fi
      say "  http://$A:$PORT" ;;
  esac
done
say "On this computer: $URL"
say ""
if [ "$SYSTEMD" = yes ]; then
  say "It starts by itself when you log in."
  if [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)" != yes ]; then
    if loginctl enable-linger "$(id -un)" </dev/null >/dev/null 2>&1; then
      say "It also starts when the computer starts, before anyone logs in."
    else
      say "To have it start when the computer starts, before anyone logs in, run once:"
      say "  sudo loginctl enable-linger $(id -un)"
    fi
  else
    say "It also starts when the computer starts, before anyone logs in."
  fi
elif [ "$WROTE_UNIT" = yes ]; then
  say "It does not start by itself yet: systemd could not be reached for this user (as happens under su or sudo)."
  say "Log in as $(id -un) directly (or over ssh) and run this installer again."
else
  say "This system does not use systemd, so Nagenli does not start by itself. Start it with:"
  say "  $DIR/nagenli -no-browser &"
  say "or add that line to how this computer starts programs (for example a @reboot line in crontab -e)."
fi
if [ -n "$FF_NOTE" ]; then
  say ""
  say "$FF_NOTE"
fi

# Settings open on the server computer, or in a browser at home that was given a one-time code made here.
# shellcheck disable=SC2086
CODE="$("$NAGENLI" -owner-code $ASK 2>/dev/null | sed -n 's/^Code: //p' || true)"
say ""
if [ -n "$CODE" ]; then
  say "To change settings from another computer at home, open it there, go to Settings and type this code"
  say "(valid 10 minutes): $CODE"
fi
say "For a new code later run: $NAGENLI -owner-code"
say "(An SSH tunnel also works: ssh -L $PORT:127.0.0.1:$PORT $(id -un)@<this computer>, then open $URL there.)"
