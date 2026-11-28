#!/bin/bash
# Puts Nagenli on a Samsung TV that is in Developer Mode, from a Mac. Run it with:
#   curl -fsSL https://quantumleapinco.github.io/nagenli-releases/install-tv-mac.sh | bash
# It changes nothing on the Mac but a small folder of its own (~/Library/Caches/Nagenli-TV): it fetches
# Samsung's own tool for talking to a television (sdb, from Samsung's Tizen download site, checked against
# a known fingerprint) and the Nagenli TV app, and hands the app to the television.
set -uo pipefail

SITE=https://quantumleapinco.github.io/nagenli-releases
SDB_URL=https://download.tizen.org/sdk/tizenstudio/official/binary/sdb_4.2.36_macos-64.zip
SDB_SHA=0bd307ac8382c857be5c2106dd5b8587b10c1c91ac1e504de8432c8276bc28c5
APP=NagenliTV0.Nagenli
DIR="$HOME/Library/Caches/Nagenli-TV"
SDB="$DIR/sdb"

say() { printf '%s\n' "$*"; }
# Samsung's tool, given nothing to read: this script itself arrives on standard input (curl | bash), and
# "sdb shell" would otherwise swallow the rest of it and wait for more.
sdb() { "$SDB" "$@" < /dev/null; }
stop() { say ""; say "$*"; say ""; exit 1; }
ask() { # the script itself arrives on standard input, so questions are read from the keyboard
  local answer=""
  printf '%s' "$1" > /dev/tty
  IFS= read -r answer < /dev/tty || true
  printf '%s' "$answer"
}

say ""
say "  Nagenli for Samsung TV"
say ""
[ "$(uname -s)" = Darwin ] || stop "This is for a Mac. On Windows use the kit from $SITE/samsung-tv.html"

# This Mac's address on the home network: the television asks for it as "Host PC IP".
MINE=""
for nic in $(route -n get default 2>/dev/null | awk '/interface:/{print $2}') en0 en1; do
  ip="$(ipconfig getifaddr "$nic" 2>/dev/null || true)"
  if [ -n "$ip" ]; then MINE="$ip"; break; fi
done
[ -n "$MINE" ] || stop "This Mac does not seem to be on a network."
say "This Mac's address (the TV's \"Host PC IP\"): $MINE"
say ""

# Samsung's tool is made for Intel Macs; a newer Mac runs it through Rosetta.
if [ "$(uname -m)" = arm64 ] && ! /usr/bin/pgrep -q oahd 2>/dev/null; then
  stop "This Mac needs Apple's Rosetta once, to run Samsung's tool. Paste this, then run the Nagenli command again:
  softwareupdate --install-rosetta --agree-to-license"
fi

mkdir -p "$DIR"
if [ ! -x "$SDB" ] || [ "$(cat "$DIR/sdb.sha" 2>/dev/null)" != "$SDB_SHA" ]; then
  say "Getting Samsung's TV tool..."
  TMP="$(mktemp -d)"
  if ! curl -fsSL "$SDB_URL" -o "$TMP/sdb.zip"; then rm -rf "$TMP"; stop "Could not download Samsung's tool. Check the internet connection and try again."; fi
  if [ "$(shasum -a 256 "$TMP/sdb.zip" | cut -d' ' -f1)" != "$SDB_SHA" ]; then rm -rf "$TMP"; stop "Samsung's tool did not arrive as expected (its fingerprint is different). Nothing was run."; fi
  if ! unzip -oq "$TMP/sdb.zip" -d "$TMP/x" || [ ! -f "$TMP/x/data/tools/sdb" ]; then rm -rf "$TMP"; stop "Samsung's tool could not be unpacked."; fi
  cp "$TMP/x/data/tools/sdb" "$SDB.new" && chmod +x "$SDB.new" && mv -f "$SDB.new" "$SDB"
  printf '%s' "$SDB_SHA" > "$DIR/sdb.sha"
  rm -rf "$TMP"
fi

say "Getting the Nagenli TV app..."
curl -fsSL "$SITE/Nagenli.wgt" -o "$DIR/Nagenli.wgt.new" || stop "Could not download the Nagenli TV app."
mv -f "$DIR/Nagenli.wgt.new" "$DIR/Nagenli.wgt"

# Televisions in Developer Mode listen on port 26101: ask every address of this network at once.
say "Looking for the TV..."
NET="${MINE%.*}"
FOUND="$DIR/found.txt"; : > "$FOUND"
for n in $(seq 1 254); do
  ( nc -z -G 1 "$NET.$n" 26101 >/dev/null 2>&1 && echo "$NET.$n" >> "$FOUND" ) &
done
wait
TVS="$(sort -u "$FOUND" | tr '\n' ' ' | sed 's/ $//')"
rm -f "$FOUND"
TV=""
case "$TVS" in
  "") say "No TV answered. Is it on, and is Developer Mode on (see the instructions)?" ;;
  *" "*) say "Found several: $TVS" ;;
  *) TV="$TVS"; say "Found a TV at $TV" ;;
esac
if [ -z "$TV" ]; then
  TV="$(ask "Type the TV's address (TV: Settings > General > Network > Network Status > IP Settings): ")"
  TV="$(printf '%s' "$TV" | tr -d '[:space:]')"
  printf '%s' "$TV" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || stop "That is not an address like 192.168.1.50."
fi

# The television says about itself (Samsung's own page on port 8001) whether Developer Mode is really on and which
# computer it will let in. That settles the two usual mistakes before anything is tried.
INFO="$(curl -fsS -m 4 "http://$TV:8001/api/v2/" 2>/dev/null | tr -d '\r\n')"
field() { printf '%s' "$INFO" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\).*/\1/p" | head -n 1; }
TVNAME="$(field modelName)"; TVDEV="$(field developerMode)"; TVHOST="$(field developerIP)"; TVFW="$(field firmwareVersion)"
[ -n "$TVNAME" ] && say "It is a $TVNAME."
if [ -n "$INFO" ] && [ -n "$TVDEV" ] && [ "$TVDEV" != 1 ]; then
  stop "Developer Mode is not on yet on this TV (the TV itself says so).
On the TV: Apps > press 1 2 3 4 5 on the remote > Developer Mode ON > Host PC IP = $MINE > OK.
Then hold the power button on the remote until the TV turns off and the Samsung logo shows again
(a short press only puts it to sleep, and the setting does not take). Then run this again."
fi
if [ -n "$TVHOST" ] && [ "$TVHOST" != "$MINE" ]; then
  BACK="$(printf '%s' "$MINE" | awk -F. '{print $4"."$3"."$2"."$1}')"
  if [ "$TVHOST" = "$BACK" ]; then
    stop "The address was typed backwards on the TV: it has $TVHOST, and this Mac is $MINE.
(When the TV's menus are in Hebrew or Arabic, the four boxes are filled from the right.)
On the TV: Apps > press 1 2 3 4 5 > Host PC IP: make it read $MINE, checking it box by box > OK.
Then hold the power button on the remote until the TV turns off and the Samsung logo shows again, and run this again."
  fi
  stop "The TV is set to let in the computer at $TVHOST, but this Mac is $MINE.
On the TV: Apps > press 1 2 3 4 5 > Host PC IP = $MINE > OK.
Then hold the power button on the remote until the TV turns off and the Samsung logo shows again, and run this again."
fi
# Does the television hang up at once? (It does that to a computer it was not told to let in.)
HANGUP="$(/usr/bin/perl -e 'use IO::Socket::INET; use IO::Select; my $s=IO::Socket::INET->new(PeerAddr=>$ARGV[0],PeerPort=>26101,Timeout=>4) or do{print "no connection";exit}; my @r=IO::Select->new($s)->can_read(3); if(!@r){print "stays open"} else { my $n=sysread($s,my $b,64); print defined($n)&&$n>0 ? "talks first" : "hangs up at once" }' "$TV" 2>/dev/null)"
DIRECT="$TV:26101"
TARGET="$DIRECT"
say "Connecting to the TV..."

# Samsung's tool runs a helper in the background. The first time (and through Rosetta on newer Macs) it can take
# many seconds to start, and a television can answer "offline" for a moment before it lets the Mac in: so this
# asks patiently, several times, instead of giving up after one try.
export SDB_CONNECT_TIMEOUT=15   # seconds the tool waits for the television to take the connection
STATE=""; CONN=""
knock() { # knock <address:port> <tries>: connect and wait until the TV says "device"
  local t="$1" n="$2" i w
  for i in $(seq 1 "$n"); do
    CONN="$(sdb connect "$t" 2>&1 | tr -d '\r')"
    for w in 1 2 3; do
      sleep 1
      STATE="$(sdb devices 2>/dev/null | tr -d '\r' | grep -F "$t" | awk '{print $2}' | head -n 1)"
      [ "$STATE" = device ] && return 0
    done
    sdb disconnect "$t" >/dev/null 2>&1   # "offline" or nothing yet: let go and ask again
  done
  return 1
}

# Some Macs do not let Samsung's tool reach the television although the Mac itself can (newer versions of macOS
# keep programs that are not Apple's off the home network, and the tool's background helper is one). So there are
# three ways, tried in turn:
#   1. the tool as it is;
#   2. the tool's helper kept in the foreground, as a child of this Terminal window;
#   3. the Mac's own perl (or nc) carrying the conversation: Samsung's tool talks to this Mac only (127.0.0.1) and
#      every byte is passed on to the television and back.
# Nothing is left running when this script ends.
RPORT=47126
FIFO="$DIR/relay.fifo"
RLOG="$DIR/relay.log"
RELAY=""; SERVER=""
stop_relay() {
  [ -n "$RELAY" ] && kill "$RELAY" >/dev/null 2>&1
  pkill -f "relay.pl $RPORT" >/dev/null 2>&1
  pkill -f "nc -l 127.0.0.1 $RPORT" >/dev/null 2>&1
  pkill -f "nc $TV 26101" >/dev/null 2>&1
  rm -f "$FIFO"
  RELAY=""
}
stop_all() { stop_relay; [ -n "$SERVER" ] && kill "$SERVER" >/dev/null 2>&1; "$SDB" kill-server >/dev/null 2>&1 < /dev/null; }
trap stop_all EXIT

cat > "$DIR/relay.pl" <<'PERL'
use strict; use IO::Socket::INET; use IO::Select;
my ($lp, $th, $tp) = @ARGV; $| = 1; $SIG{CHLD} = 'IGNORE';
my $l = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $lp, Listen => 5, ReuseAddr => 1) or do { print "listen failed: $!\n"; exit 1 };
print "listening\n";
while (my $c = $l->accept) {
  my $t = IO::Socket::INET->new(PeerAddr => $th, PeerPort => $tp, Timeout => 8);
  if (!$t) { print "tv connect failed: $!\n"; close $c; next; }
  print "passing\n";
  my $pid = fork();
  if (defined $pid && $pid == 0) {
    close $l; binmode $c; binmode $t;
    my $s = IO::Select->new($c, $t);
    LOOP: while (my @r = $s->can_read) {
      for my $h (@r) {
        my $n = sysread($h, my $buf, 65536);
        last LOOP unless $n;
        my $o = ($h == $c) ? $t : $c; my $off = 0;
        while ($off < $n) { my $w = syswrite($o, $buf, $n - $off, $off); last LOOP unless defined $w; $off += $w; }
      }
    }
    exit 0;
  }
  close $c; close $t;
}
PERL

start_relay() {
  stop_relay
  : > "$RLOG"
  if [ -x /usr/bin/perl ]; then
    /usr/bin/perl "$DIR/relay.pl" "$RPORT" "$TV" 26101 >> "$RLOG" 2>&1 < /dev/null &
    RELAY=$!
  else
    ( while :; do
        rm -f "$FIFO"; mkfifo "$FIFO" || exit 1
        nc -l 127.0.0.1 "$RPORT" < "$FIFO" | nc "$TV" 26101 > "$FIFO"
        sleep 1
      done ) > /dev/null 2>&1 < /dev/null &
    RELAY=$!
  fi
  disown "$RELAY" 2>/dev/null || true   # so the shell says nothing when it is stopped
  sleep 1
}
fresh_server() { # fresh_server daemon|front
  "$SDB" kill-server >/dev/null 2>&1 < /dev/null
  [ -n "$SERVER" ] && kill "$SERVER" >/dev/null 2>&1; SERVER=""
  rm -f /tmp/sdb.log
  if [ "$1" = front ]; then
    SDB_DEBUG=1 "$SDB" fork-server server >/dev/null 2>&1 < /dev/null &
    SERVER=$!; disown "$SERVER" 2>/dev/null || true
    sleep 2
  else
    sdb start-server >/dev/null 2>&1
  fi
}

sleep 2                         # the search above knocked on the TV's door: let it settle before the real visit
TRIED=""
VIA="direct"; TRIED="direct"
fresh_server daemon
if ! knock "$DIRECT" 2; then
  if nc -z -G 2 "$TV" 26101 >/dev/null 2>&1; then
    say "Taking another way to the TV..."
    VIA="front"; TRIED="$TRIED front"
    fresh_server front
    if ! knock "$DIRECT" 2; then
      VIA="relay"; TRIED="$TRIED relay"
      for round in 1 2; do
        [ "$round" = 2 ] && fresh_server daemon
        start_relay
        TARGET="127.0.0.1:$RPORT"
        knock "$TARGET" 2 && break
      done
      LISTEN="$(lsof -nP -iTCP:"$RPORT" -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $1}' | head -n 1)"
      RSAID="$(tr '\n' ',' < "$RLOG" 2>/dev/null)"
      [ "$STATE" = device ] || { stop_relay; TARGET="$DIRECT"; }
    fi
  else
    say "Still waiting for the TV to answer..."
    knock "$DIRECT" 6
  fi
fi
if [ "$STATE" != device ]; then
  VER="$(sdb version 2>&1 | head -n 1 | tr -d '\r')"
  LIST="$(sdb devices 2>&1 | tr -d '\r')"
  # One more try with the tool's own trace on: its last lines say what the system answered (for the report below).
  sdb kill-server >/dev/null 2>&1
  TRACE="$(SDB_DEBUG=1 SDB_TRACE=all "$SDB" connect "$DIRECT" < /dev/null 2>&1 | tr -d '\r' | grep -i 'errno\|route\|refus\|denied\|timed\|timeout\|unreach\|fail' | tail -n 4 | tr '\n' ';')"
  MACOS="$(sw_vers -productVersion 2>/dev/null) $(uname -m)"
  SLOG="$(grep -i 'errno\|route\|refus\|denied\|timed\|unreach\|fail\|error' /tmp/sdb.log 2>/dev/null | tail -n 5 | cut -c1-160 | tr '
' ';')"
  sdb kill-server >/dev/null 2>&1
  case "$STATE" in
    unauthorized) WHY="The TV saw this Mac but does not trust it: its \"Host PC IP\" is not this Mac's address ($MINE), or the TV was not fully restarted after it was set." ;;
    offline)      WHY="The TV answered but stayed \"offline\": it was not fully restarted after Developer Mode was set (hold the power button until the Samsung logo shows, or unplug it for half a minute)." ;;
    "")           if [ -z "$VER" ] || printf '%s' "$VER" | grep -qi 'bad cpu\|cannot execute\|not found\|killed'; then
                    WHY="Samsung's tool did not start on this Mac ($VER). On a newer Mac run:  softwareupdate --install-rosetta --agree-to-license"
                  elif printf '%s' "$SLOG$RSAID" | grep -qi 'reset by peer\|passing' ; then
                    WHY="This Mac reaches the TV, but the TV hangs up as soon as the install tool speaks to it.
The TV does that when it was not fully restarted after Developer Mode was set: hold the power button on the
remote until the TV turns off and the Samsung logo shows again (or unplug it for half a minute), then run this again.
If it was restarted that way, send the lines below: this TV model may need a different tool."
                  elif nc -z -G 2 "$TV" 26101 >/dev/null 2>&1; then
                    # The Mac's own tool reaches the TV, Samsung's does not: newer macOS keeps programs that are not
                    # Apple's off the home network until Terminal is allowed there.
                    WHY="This Mac is stopping Samsung's tool from reaching devices at home.
Open System Settings > Privacy & Security > Local Network, and switch Terminal ON
(if it is already on, switch it off and on again). Then close Terminal, open it, and run this again."
                  else
                    WHY="The TV did not accept the connection. If a VPN is on, switch it off; if this Mac is on both cable and Wi-Fi, switch one off; then run this again."
                  fi ;;
    *)            WHY="The TV answered \"$STATE\"." ;;
  esac
  stop "The TV at $TV did not let this Mac in.
$WHY

Check on the TV: Apps > press 1 2 3 4 5 on the remote > Developer Mode ON > Host PC IP = $MINE
Then hold the power button until the TV restarts (the Samsung logo shows), and run this again.

If it still fails, send these lines to the person who invited you:
  mac: $MINE   tv: $DIRECT   state: ${STATE:-none}   ways tried: ${TRIED:-direct}
  tool: ${VER:-did not run}
  connect: ${CONN:-no answer}
  devices: $(printf '%s' "$LIST" | tr '\n' ';')
  macOS: $MACOS
  tv says: model=${TVNAME:-?} firmware=${TVFW:-?} developerMode=${TVDEV:-?} developerIP=${TVHOST:-?} on connect: ${HANGUP:-?}
  relay: listener=${LISTEN:-none} said=${RSAID:-nothing}
  log: $SLOG
  trace: ${TRACE:-none}"
fi

DUID="$(sdb -s "$TARGET" shell 0 getduid 2>/dev/null | tr -d '\r\n ')"
say "TV code (DUID): $DUID"
say ""
say "Installing Nagenli (about half a minute)..."

# Where the television takes packages from; every Samsung TV says so itself.
TOOLPATH="$(sdb -s "$TARGET" capability 2>/dev/null | tr -d '\r' | sed -n 's/^sdk_toolpath:\(.*\)$/\1/p' | head -n 1)"
[ -n "$TOOLPATH" ] || TOOLPATH=/home/owner/share/tmp/sdk_tools
sdb -s "$TARGET" push "$DIR/Nagenli.wgt" "$TOOLPATH/tmp/Nagenli.wgt" >/dev/null 2>&1
OUT="$(sdb -s "$TARGET" shell 0 vd_appinstall "$APP" "$TOOLPATH/tmp/Nagenli.wgt" 2>&1 | tr -d '\r')"

if printf '%s' "$OUT" | grep -q 'install completed' && ! printf '%s' "$OUT" | grep -qi 'fail'; then
  sdb -s "$TARGET" shell 0 was_execute "$APP" >/dev/null 2>&1
  sdb kill-server >/dev/null 2>&1
  say ""
  say "Nagenli is on the TV. It is opening now; next time it is in Apps."
  say ""
  exit 0
fi

MODEL="$(sdb -s "$TARGET" capability 2>/dev/null | tr -d '\r' | grep -E '^(product_version|platform_version|profile_name):' | tr '\n' ' ')"
sdb kill-server >/dev/null 2>&1
printf 'Nagenli TV install refused\nTV code (DUID): %s\nTV: %s\n%s\n' "$DUID" "$MODEL" "$OUT" | pbcopy 2>/dev/null || true
stop "The TV refused the app. This is what it answered:
$OUT

Some Samsung TVs take only apps signed for that one TV. Send these lines to the person who invited you
(they were copied, just paste them in a message):

    TV code (DUID): $DUID
    TV: $MODEL

They will tell you what to do next."
