#!/bin/sh
# Runs upstream's supervisord (nginx, php-fpm, queue workers, scheduler) and
# exits non-zero when it, nginx or php-fpm stops for good, so Railway's
# ON_FAILURE restart policy brings the service back. supervisord on its own
# keeps running (and would exit 0) with a dead web server.
set -u
/usr/bin/supervisord -c /etc/supervisord.conf &
sup_pid=$!

stop() {
    kill -TERM "$sup_pid" 2>/dev/null || true
    wait "$sup_pid" 2>/dev/null || true
    exit 0
}
trap stop TERM INT

sleep 10
while :; do
    if ! kill -0 "$sup_pid" 2>/dev/null; then
        echo "railway: supervisord exited, stopping the container" >&2
        exit 1
    fi
    bad="$(supervisorctl -c /etc/supervisord.conf status nginx php-fpm 2>&1 | grep -E 'FATAL|EXITED|BACKOFF|STOPPED|refused|no such' || true)"
    if [ -n "$bad" ]; then
        echo "railway: core process down: $bad" >&2
        kill -TERM "$sup_pid" 2>/dev/null || true
        exit 1
    fi
    sleep 10 &
    wait $! || true
done
