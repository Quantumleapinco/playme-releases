#!/bin/bash
# Installs Nagenli on a Mac, or repairs/upgrades an existing install. Run it with:
#   curl -fsSL https://raw.githubusercontent.com/Quantumleapinco/nagenli-releases/master/install-mac.sh | bash
# It puts Nagenli in ~/Library/Nagenli, makes it start with the Mac (a LaunchAgent) and opens it.
# Nagenli updates itself from then on. Nothing here needs an administrator password.
set -euo pipefail

FEED=https://raw.githubusercontent.com/Quantumleapinco/nagenli-releases/master
DIR="$HOME/Library/Nagenli"
LABEL=app.nagenli.server
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
URL=http://127.0.0.1:8686

case "$(uname -m)" in
  arm64) ARCH=arm64 ;;
  x86_64) ARCH=amd64 ;;
  *) echo "This Mac's processor ($(uname -m)) is not supported." >&2; exit 1 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Nagenli..."
curl -fsSL "$FEED/manifest.json" -o "$TMP/manifest.json"
curl -fsSL "$FEED/nagenli-mac-$ARCH" -o "$TMP/nagenli"

# The manifest lists each file with its sha256; take the one of our file.
WANT="$(tr -d '\n' < "$TMP/manifest.json" \
  | grep -oE "\"nagenli-mac-$ARCH\" *: *\{[^}]*\}" \
  | grep -oE '"sha256" *: *"[0-9a-f]{64}"' \
  | grep -oE '[0-9a-f]{64}' | head -n 1 || true)"
if [ -z "$WANT" ]; then
  echo "This release has no Nagenli for this Mac yet." >&2
  exit 1
fi
GOT="$(shasum -a 256 "$TMP/nagenli" | cut -d' ' -f1)"
if [ "$WANT" != "$GOT" ]; then
  echo "The download is damaged (its fingerprint does not match the release). Try again." >&2
  exit 1
fi

# ffmpeg and ffprobe: use the ones already on this Mac, else fetch static builds beside Nagenli. The build is a
# fixed one (version 9.1 from ffmpeg.martin-riedl.de) and nothing is used that does not match the fingerprint below.
# Nagenli also fetches its own tested build after it starts (internal/server/tools.go, the same files) and uses that
# one first; this copy lets it play at once and stays as the fallback. Change the two places together.
case "$ARCH" in
  arm64)
    FFDIR=1795207104_9.1
    FF_ffmpeg=1f66e9a690a7f1c9e60b012379f8869c11818d1797f45b21dbb2f2564ba61ae1
    FF_ffprobe=6ef2df5f575042923a28537ab37adf936f28bf3e7b85de23a1447ed447ec1dbd ;;
  amd64)
    FFDIR=1795212433_9.1
    FF_ffmpeg=35b3d82cccc2c1d644d49d15f5e57eb913a08ef68f798042c90eecec62c51f1e
    FF_ffprobe=41ca7b7cba7992e33f1da3f1bf54db8ec103a4d387b1bfac3162062e8b1074ad ;;
esac
have() {
  [ -x "$DIR/$1" ] || command -v "$1" >/dev/null 2>&1 || [ -x "/opt/homebrew/bin/$1" ] || [ -x "/usr/local/bin/$1" ]
}
mkdir -p "$DIR"
for tool in ffmpeg ffprobe; do
  if have "$tool"; then continue; fi
  echo "Downloading $tool..."
  mkdir -p "$TMP/$tool.d"
  if ! curl -fsSL "https://ffmpeg.martin-riedl.de/download/macos/$ARCH/$FFDIR/$tool.zip" -o "$TMP/$tool.zip"; then
    echo "Could not get $tool. Install it with:  brew install ffmpeg  and run this command again." >&2
    exit 1
  fi
  eval "WANT=\$FF_$tool"
  if [ "$(shasum -a 256 "$TMP/$tool.zip" | cut -d' ' -f1)" != "$WANT" ]; then
    echo "The download of $tool is not the build this installer expects (its fingerprint does not match). Nothing was installed. Install it with:  brew install ffmpeg  and run this command again." >&2
    exit 1
  fi
  if ! unzip -oq "$TMP/$tool.zip" -d "$TMP/$tool.d" || [ ! -f "$TMP/$tool.d/$tool" ]; then
    echo "Could not open $tool. Install it with:  brew install ffmpeg  and run this command again." >&2
    exit 1
  fi
  cp "$TMP/$tool.d/$tool" "$DIR/$tool.new"
  chmod +x "$DIR/$tool.new"
  xattr -d com.apple.quarantine "$DIR/$tool.new" 2>/dev/null || true
  mv -f "$DIR/$tool.new" "$DIR/$tool"
done

# Stop a Nagenli that is already running, then put the new program in place.
UIDN="$(id -u)"
launchctl bootout "gui/$UIDN/$LABEL" 2>/dev/null || true
# The product was called PlayMe before: a Mac that had it under that name loses its LaunchAgent,
# so two programs never start at login. (Its program and data folders are left as they are.)
OLD_LABEL=app.playme.server
launchctl bootout "gui/$UIDN/$OLD_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
cp "$TMP/nagenli" "$DIR/nagenli.new"
chmod +x "$DIR/nagenli.new"
xattr -d com.apple.quarantine "$DIR/nagenli.new" 2>/dev/null || true
mv -f "$DIR/nagenli.new" "$DIR/nagenli"

# Start with the Mac: quietly (no page opens at login), and again if it ever stops.
XDIR="$(printf '%s' "$DIR" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$XDIR/nagenli</string>
		<string>-no-browser</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>StandardOutPath</key>
	<string>/dev/null</string>
	<key>StandardErrorPath</key>
	<string>/dev/null</string>
</dict>
</plist>
PLISTEOF
# bootout can still be finishing: a few tries, a second apart.
for TRY in 1 2 3 4 5; do
  if launchctl bootstrap "gui/$UIDN" "$PLIST" 2>/dev/null; then break; fi
  if [ "$TRY" = 5 ]; then launchctl bootstrap "gui/$UIDN" "$PLIST"; fi
  sleep 1
done

echo "Starting Nagenli..."
for _ in $(seq 1 40); do
  if curl -s -o /dev/null "$URL"; then break; fi
  sleep 0.5
done
if ! curl -s -o /dev/null "$URL"; then
  echo "Nagenli did not start. Its log is in ~/Library/Application Support/Nagenli/nagenli.log" >&2
  exit 1
fi
open "$URL"
echo "Nagenli is running and starts with the Mac."
echo "macOS may ask to allow incoming connections and access to folders: allow them."
