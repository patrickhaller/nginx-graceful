#!/bin/bash
# https://www.nginx.com/resources/wiki/start/topics/tutorials/commandline/
die() { echo "$@"; exit 1; }
error_handler() {
    printf 'Error at %s:%s while handling `%s`\nStacktrace:\n' \
        "$(basename ${BASH_SOURCE[0]})" "${BASH_LINENO[0]}" "$BASH_COMMAND" >&2
    for k in ${!FUNCNAME[@]}; do
        printf '  %s:%s called %s\n' \
            "$(basename ${BASH_SOURCE[$k]})" "${BASH_LINENO[$k]}" "${FUNCNAME[$k]}"
    done | tac >&2
}
run() { if [[ "$HOST" = '' ]]; then command "$@"; else ssh $HOST "$@"; fi; }
log() { run logger -s -t 'nginx-graceful' "$*" ; }
ps() { run ps "$@"; }
kill() { run kill "$@"; }
is_pid() { ps -p $1 &>/dev/null ; }
nl() { for i in "$@"; do echo "$i"; done; }
ls_new_master() { comm -23 <( nl $1 ) <( nl $2 ); }
ls_kids() { ps h -C nginx -o pid,ppid | awk -v ppid=$1 '$2 == ppid { print $1 }'; }

rollback() {
    is_pid $OLD && kill -s 'HUP'  $OLD
    is_pid $NEW && kill -s 'QUIT' $NEW
    exit 0
}


HOST="$1"; shift

set -e -u -E
trap error_handler ERR

ps h -C nginx >/dev/null || die "nginx not running?"

OLD=$( ls_kids 1 )
is_pid "$OLD" ||
    die "old master '${OLD}' is not a valid pid"

old_kids=$( ls_kids $OLD )

kill -s 'USR2' $OLD
new_kids=$( ls_kids $OLD )
[[ "$new_kids" = "$old_kids" ]] &&
    die "failed to spawn new master"

NEW=$( ls_new_master "$new_kids" "$old_kids" )
is_pid "$NEW" ||
    die "new master '${NEW}' is not a valid pid"

log "old master = ${OLD}, kids = " ${old_kids}
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
