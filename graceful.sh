#!/bin/bash
# https://www.nginx.com/resources/wiki/start/topics/tutorials/commandline/
die() { echo "$@"; exit 1; }
error_handler() {
    echo "Error in ${BASH_SOURCE[1]} at line ${BASH_LINENO[0]}, exiting..."
    local stack=${FUNCNAME[*]}
    stack=${stack/error_handler }
    stack=${stack// /<-}
    echo "  Stacktrace = ${stack}"
    exit 1
}
run() { [[ "$HOST" = '' ]] && command "$@" || ssh $HOST "$@"; }
log() { run logger -t 'nginx-graceful' "$*" ; }
ps() { run ps "$@"; }
kill() { run kill "$@"; }
is_pid() { ps -p $1 &>/dev/null ; }
ls_kids() { ps h -C nginx -o pid,ppid | awk -v ppid=$1 '$2 == ppid { print $1 }'; }
rollback() {
    echo -n "rolling back to pid ${OLD}... "
    is_pid $OLD &&
        kill -s 'HUP' $OLD
    echo -n "killing new master ${NEW}... "
    is_pid $NEW &&
        kill -s 'QUIT' $NEW
    echo 'done'
    exit 0
}
nl() { for i in "$@"; do echo "$i"; done; }
ls_new_master() {
    local oldmaster="$1"; shift
    local oldkids="$1"; shift
    comm -23 <( ls_kids $oldmaster ) <( nl $oldkids )
}


HOST="$1"; shift

set -e -u -E
trap error_handler ERR

ps h -C nginx >/dev/null || die "nginx not running?"

OLD=$( ls_kids 1)
kids=$( ls_kids $OLD )
log "old master = ${OLD}, kids = " ${kids}

kill -s 'USR2' $OLD
[[ "$( ls_kids $OLD )" = "$kids" ]] && die "failed to spawn new master"
NEW=$( ls_new_master "$OLD" "$kids" )
log "found new master = ${NEW}"

trap rollback INT

kill -s 'WINCH' $OLD
while [[ "$( ls_kids $OLD | wc -w )" != 1 ]]; do
    echo "waiting for old workers to close: $( ls_kids $OLD | grep -xv $NEW )"
    sleep 1
done

echo -n 'commit or rollback> '; read commit

if [[ "$commit" = "commit" ]]; then
    log "promoting new master ${NEW}, killing old ${OLD}"
    kill -s 'QUIT' $OLD
else
    log "rolling back to old master = ${OLD}"
    rollback
fi

exit 0
