#!/bin/zsh
# Starts every local test server in the background (idempotent). Logs: $TEST_SERVERS_DIR/logs/
# Servers keep running after the shell exits; they do not come back after a reboot.
T="${TEST_SERVERS_DIR:-$HOME/test-servers}"
[ -d "$T" ] || { echo "No test server folder at $T (set TEST_SERVERS_DIR)"; exit 1; }
cd "$T"; mkdir -p logs
port_up() { lsof -iTCP:$1 -sTCP:LISTEN -n -P >/dev/null 2>&1; }
start() { # name port command...
  local name=$1 port=$2; shift 2
  if port_up $port; then echo "$name already listening on :$port"; return; fi
  nohup "$@" >> "$T/logs/$name.log" 2>&1 < /dev/null &
  echo $! > "$T/logs/$name.pid"; disown 2>/dev/null
  echo "started $name (pid $!) on :$port"
}
JAVA="${JAVA:-/usr/bin/java}"
[ -f komga/komga.jar ] && start komga 25600 $JAVA -Xmx1g -jar komga/komga.jar --server.port=25600 --komga.config-dir="$T/komga/config"
[ -x kavita/Kavita/Kavita ] && (cd kavita/Kavita && start kavita 5005 ./Kavita)
[ -f suwayomi/suwayomi.jar ] && start suwayomi 4567 $JAVA -Xmx1g \
  -Dsuwayomi.tachidesk.config.server.rootDir="$T/suwayomi/data" \
  -Dsuwayomi.tachidesk.config.server.ip=0.0.0.0 \
  -Dsuwayomi.tachidesk.config.server.port=4567 \
  -Dsuwayomi.tachidesk.config.server.localSourcePath="$T/suwayomi/local" \
  -Dsuwayomi.tachidesk.config.server.initialOpenInBrowserEnabled=false \
  -Dsuwayomi.tachidesk.config.server.systemTrayEnabled=false \
  -Dsuwayomi.tachidesk.config.server.webUIEnabled=false \
  -jar suwayomi/suwayomi.jar
[ -x stump/stump_server ] && STUMP_PORT=10801 STUMP_CONFIG_DIR="$T/stump/config" STUMP_CLIENT_DIR="$T/stump/client" \
  STUMP_ENABLE_UPLOAD=false start stump 10801 stump/stump_server
CAL="$T/calibre/calibre.app/Contents/MacOS"
[ -x "$CAL/calibre-server" ] && start calibre 8080 "$CAL/calibre-server" --port=8080 --listen-on=0.0.0.0 \
  --enable-auth --userdb="$T/calibre/users.sqlite" --disable-use-bonjour "$T/calibre/library"
[ -x tools/cwvenv/bin/cps ] && CALIBRE_DBPATH="$T/calibreweb" start calibreweb 8083 tools/cwvenv/bin/cps -p "$T/calibreweb/app.db" -g "$T/calibreweb/gdrive.db"
[ -x tools/codexvenv/bin/codex ] && CODEX_CONFIG_DIR="$T/codex" start codex 9810 tools/codexvenv/bin/codex
true
