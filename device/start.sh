#!/system/bin/sh
base=/data/local/ryuo180
enabled="$base/enabled"
package=com.baiyi.homeui.hshomeui
last_pid=
applied_at=0

[ -f "$enabled" ] || exit 0
[ "$(getprop ro.product.device)" = cm16 ] || exit 2
cd "$base" || exit 2

while [ -f "$enabled" ]; do
    if [ "$(getprop sys.boot_completed)" != 1 ]; then
        sleep 4
        continue
    fi
    current="$(pidof "$package")"
    case "$current" in
        ''|*[!0-9]*) sleep 4; continue ;;
    esac
    if [ "$current" = "$last_pid" ]; then
        sleep 4
        continue
    fi
    now="$(date +%s)"
    if [ "$applied_at" -ne 0 ] && [ "$((now - applied_at))" -lt 25 ]; then
        log -t RYUO180 "HomeUI changed PID soon after injection; stopped for this boot"
        exit 3
    fi
    sleep 5
    [ -f "$enabled" ] || exit 0
    [ "$(pidof "$package")" = "$current" ] || continue
    if ! timeout 18 "$base/inject" -p "$current" -s "$base/rotate.bundle.js" -e >"$base/last-run.log" 2>&1; then
        log -t RYUO180 "Injection failed; stopped for this boot"
        exit 4
    fi
    last_pid="$current"
    applied_at="$(date +%s)"
    log -t RYUO180 "Attached to HomeUI PID $current"
done
