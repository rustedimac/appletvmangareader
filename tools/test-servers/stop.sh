#!/bin/zsh
# Stops every local test server started by start.sh (by listening port).
T="${TEST_SERVERS_DIR:-$HOME/test-servers}"
for p in 25600:komga 5005:kavita 4567:suwayomi 10801:stump 8080:calibre 8083:calibreweb 9810:codex; do
  port=${p%%:*}; name=${p#*:}
  pids=$(lsof -tiTCP:$port -sTCP:LISTEN -n -P 2>/dev/null)
  if [ -n "$pids" ]; then kill $=pids && echo "stopped $name (:$port)"; else echo "$name not running"; fi
  rm -f "$T/logs/$name.pid"
done
