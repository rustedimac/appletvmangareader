#!/bin/zsh
# Prints up/down for each local test server (any HTTP answer, even 401, counts as up).
check() { # name url
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$2")
  if [ "$code" != "000" ]; then printf "%-11s UP   (%s) %s\n" $1 $code $2; else printf "%-11s DOWN %s\n" $1 $2; fi
}
check komga      http://localhost:25600/api/v1/libraries
check kavita     http://localhost:5005/api/health
check suwayomi   http://localhost:4567/api/graphql
check stump      http://localhost:10801/api/v2/ping
check calibre    http://localhost:8080/ajax/library-info
check calibreweb http://localhost:8083/opds
check codex      http://localhost:9810/opds/v1.2/
