#!/bin/sh
# Railway start script for ProjectSend (official image).
#  1. Refuse to start without a database, Redis or first administrator, so the
#     web setup screen is never open to the first visitor.
#  2. Listen on Railway's PORT and size nginx, php-fpm and the queue workers
#     to the service's memory and CPU limits (Railway hosts show 32+ CPUs).
#  3. Hand over to upstream's entrypoint (APP_KEY on the volume, wait for the
#     database, migrate, create the first administrator), which then runs
#     railway-supervise (supervisord plus a watchdog that exits non-zero).
set -eu

for v in DB_HOST DB_PASSWORD REDIS_HOST ADMIN_EMAIL ADMIN_PASSWORD; do
    eval "val=\${$v:-}"
    if [ -z "$val" ]; then
        echo "railway: $v is empty. Set it in the service variables (the template fills it) and redeploy." >&2
        exit 1
    fi
done
case "$ADMIN_EMAIL" in
    *@*.*) ;;
    *) echo "railway: ADMIN_EMAIL ('$ADMIN_EMAIL') is not an email address. Fix it and redeploy." >&2; exit 1 ;;
esac
if [ "${#ADMIN_PASSWORD}" -lt 12 ]; then
    echo "railway: ADMIN_PASSWORD must be at least 12 characters (ProjectSend's password policy)." >&2
    exit 1
fi

# Settings Railway users should not have to think about. The storage/.env
# that upstream copies from .env.example on first boot holds development
# values (debug logging, a "mailpit" mail host); the environment wins over it.
export APP_ENV=production APP_DEBUG=false
export APP_URL="${APP_URL:-http://localhost}"
export LOG_LEVEL="${LOG_LEVEL:-warning}"
export LOG_STACK="${LOG_STACK:-stderr}"
export DB_CONNECTION="${DB_CONNECTION:-mysql}"
export DB_PORT="${DB_PORT:-3306}"
export DB_DATABASE="${DB_DATABASE:-railway}"
export DB_USERNAME="${DB_USERNAME:-root}"
export REDIS_PORT="${REDIS_PORT:-6379}"
export CACHE_STORE="${CACHE_STORE:-redis}"
export SESSION_DRIVER="${SESSION_DRIVER:-redis}"
export QUEUE_CONNECTION="${QUEUE_CONNECTION:-redis}"
# Mail is set up later under System > Settings > Email; until then, log it.
export MAIL_MAILER="${MAIL_MAILER:-log}"
# Only Railway's edge proxy can reach the container, so trusting it is safe
# and gives the app the real client IP for rate limits and download logs.
export TRUSTED_PROXIES="${TRUSTED_PROXIES:-*}"
export ADMIN_NAME="${ADMIN_NAME:-Administrator}"

# Memory and CPUs available to this service (cgroup v2, then v1).
mem_mb=""
if [ -r /sys/fs/cgroup/memory.max ]; then
    raw="$(cat /sys/fs/cgroup/memory.max)"
    [ "$raw" != "max" ] && mem_mb=$((raw / 1048576))
elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    raw="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)"
    [ "$raw" -lt 1099511627776 ] && mem_mb=$((raw / 1048576))
fi
[ -z "$mem_mb" ] && mem_mb=4096
cpus=""
if [ -r /sys/fs/cgroup/cpu.max ]; then
    read -r quota period < /sys/fs/cgroup/cpu.max || true
    if [ "${quota:-max}" != "max" ] && [ "${period:-0}" -gt 0 ]; then
        cpus=$(( (quota + period - 1) / period ))
    fi
fi
[ -z "$cpus" ] && cpus="$(nproc 2>/dev/null || echo 2)"
[ "$cpus" -lt 1 ] && cpus=1
[ "$cpus" -gt 4 ] && cpus=4

# nginx: listen on PORT, one worker per allowed CPU (not per host CPU).
PORT="${PORT:-8080}"
sed -i "s/^\(\s*\)listen 80 default_server;/\1listen ${PORT} default_server;/" /etc/nginx/http.d/default.conf
grep -q "listen ${PORT} default_server;" /etc/nginx/http.d/default.conf || { echo "railway: could not set the nginx port" >&2; exit 1; }
sed -i "s/^worker_processes .*;/worker_processes ${cpus};/" /etc/nginx/nginx.conf
grep -q "^worker_processes ${cpus};" /etc/nginx/nginx.conf || { echo "railway: could not set nginx worker_processes" >&2; exit 1; }

# php-fpm: a last-loaded pool file wins over upstream's zz-www-pool.conf.
if [ "$mem_mb" -lt 900 ]; then
    children=4; php_mem=192; opcache=96; small=1
elif [ "$mem_mb" -lt 2000 ]; then
    children=6; php_mem=256; opcache=128; small=0
else
    children=10; php_mem=256; opcache=192; small=0
fi
children="${PHP_FPM_MAX_CHILDREN:-$children}"
cat > /usr/local/etc/php-fpm.d/zzz-railway.conf <<POOL
[www]
pm = ondemand
pm.max_children = ${children}
pm.process_idle_timeout = 30s
pm.max_requests = 500
POOL
cat > /usr/local/etc/php/conf.d/zz-railway.ini <<INI
memory_limit = ${php_mem}M
opcache.memory_consumption = ${opcache}
INI

# Queue workers: upstream runs three (default, zips, scans). Below 900 MB one
# worker serves all three queues in that order, which upstream supports.
conf=/etc/supervisord.conf
if [ "$small" = 1 ] && [ "${PROJECTSEND_SPLIT_WORKERS:-0}" != 1 ]; then
    awk '
        /^\[program:queue-zips\]/ || /^\[program:queue-scans\]/ { skip=1; next }
        /^\[/ { skip=0 }
        !skip { print }
    ' "$conf" > /tmp/supervisord.conf
    sed -i 's#artisan queue:work --queue=default --max-time=3600 --tries=3#artisan queue:work --queue=default,zips,scans --max-time=3600 --tries=3#' /tmp/supervisord.conf
    grep -q 'queue=default,zips,scans' /tmp/supervisord.conf || { echo "railway: could not merge the queue workers" >&2; exit 1; }
    cat /tmp/supervisord.conf > "$conf"
    workers="1 (default,zips,scans)"
else
    workers="3 (default | zips | scans)"
fi
# Let the watchdog ask supervisord for its programs' state.
if ! grep -q '^\[unix_http_server\]' "$conf"; then
    cat >> "$conf" <<SUP

[unix_http_server]
file=/run/supervisor.sock
chmod=0700

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///run/supervisor.sock
SUP
fi

echo "railway: ${mem_mb} MB / ${cpus} CPU -> nginx workers ${cpus}, php-fpm ondemand max ${children}, memory_limit ${php_mem}M, queue workers ${workers}"
exec projectsend-entrypoint railway-supervise
