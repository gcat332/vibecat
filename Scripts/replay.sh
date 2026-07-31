#!/usr/bin/env bash
# Replays a Claude Code hook payload against a running vibecat-hook.
#
#   Scripts/replay.sh permission   # a Bash command needing approval
#   Scripts/replay.sh stop         # a finished turn
#
# Point it at a scratch socket so it never touches the real one:
#   VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission
set -euo pipefail

case "${1:-permission}" in
  permission)
    payload='{"hook_event_name":"PreToolUse","session_id":"dev-1","cwd":"'"$PWD"'","tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}'
    ;;
  stop)
    payload='{"hook_event_name":"Stop","session_id":"dev-1","cwd":"'"$PWD"'","model":"Opus 4.8","reasoning_effort":"high"}'
    ;;
  notification)
    payload='{"hook_event_name":"Notification","session_id":"dev-1","cwd":"'"$PWD"'","message":"Claude needs your permission"}'
    ;;
  *)
    echo "usage: $0 [permission|stop|notification]" >&2
    exit 2
    ;;
esac

echo "$payload" | swift run vibecat-hook claude-code
echo "(exit $?)"
