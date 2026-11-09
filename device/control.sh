#!/system/bin/sh
set -eu

base=/data/local/ryuo180
hook=/vendor/etc/init/ryuo180.rc
stage=/vendor/etc/init/ryuo180.rc.staging
original_vendor=198a34117a131d99d203a7c5c3c3a89fea21026c749dcc6beb58fc8b80bf6ac7
package=com.baiyi.homeui.hshomeui

die() {
    echo "$*" >&2
    exit 1
}

[ "$(id -u)" = 0 ] || die "Root ADB shell required"
[ "$(getprop ro.product.device)" = cm16 ] || die "Expected cm16"

vendor_device() {
    device="$(readlink -f /dev/block/mapper/vendor)"
    case "$device" in
        /dev/block/dm-[0-9]*) ;;
        *) die "Unexpected vendor mapping: $device" ;;
    esac
    grep -q "^$device /vendor ext4 ro," /proc/mounts || die "Expected read-only ext4 vendor"
    [ "$(blockdev --getro "$device")" = 1 ] || die "Vendor block device is not read-only"
}

restore_vendor() {
    rc=$?
    trap - EXIT
    set +e
    if [ "${reserve_saved:-}" ]; then
        printf '%s\n' "$reserve_saved" > "$reserve" || rc=1
    fi
    if [ "${stage_created:-}" ]; then
        rm -f "$stage" || rc=1
    fi
    sync || rc=1
    if [ "${vendor_mounted_rw:-}" ]; then
        mount -o remount,ro /vendor || rc=1
    fi
    blockdev --setro "$device" || rc=1
    exit "$rc"
}

open_vendor() {
    trap restore_vendor EXIT
    blockdev --setrw "$device"
    mount -o remount,rw /vendor
    vendor_mounted_rw=1
}

case "${1:-status}" in
    status)
        if [ -f "$base/enabled" ]; then echo enabled; else echo disabled; fi
        echo "Service: $(getprop init.svc.ryuo180)"
        ;;
    install-inactive)
        [ ! -e "$base/enabled" ] || die "Disable rotation before installing"
        [ ! -e "$hook" ] && [ ! -e "$stage" ] || die "Startup file already exists"
        [ -s "$base/ryuo180.rc" ] && [ -s "$base/rotate.bundle.js" ] &&
            [ -x "$base/inject" ] || die "Incomplete payload"
        sh -n "$base/start.sh"
        vendor_device
        set -- $(sha256sum "$device")
        [ "$1" = "$original_vendor" ] || die "Vendor image does not match the tested stock image"
        reserve="/sys/fs/ext4/${device##*/}/reserved_clusters"
        [ -w "$reserve" ] || die "Cannot access the temporary ext4 allocation reserve"
        reserve_saved="$(cat "$reserve")"
        case "$reserve_saved" in ''|*[!0-9]*) die "Unexpected reserve value" ;; esac
        open_vendor
        # The tested image had 203 free clusters, below the kernel's default reserve.
        # Lower only the runtime reserve for this write and restore it in the trap.
        if [ "$reserve_saved" -gt 128 ]; then printf '128\n' > "$reserve"; fi
        stage_created=1
        cat "$base/ryuo180.rc" > "$stage"
        chmod 644 "$stage"
        chown 0:0 "$stage"
        cmp "$base/ryuo180.rc" "$stage"
        mv "$stage" "$hook"
        restorecon "$hook"
        cmp "$base/ryuo180.rc" "$hook"
        echo "Startup hook installed with rotation disabled"
        ;;
    enable)
        cmp "$base/ryuo180.rc" "$hook" || die "Unexpected startup hook"
        touch "$base/enabled"
        if [ "$(getprop init.svc.ryuo180)" != running ]; then
            setprop ctl.start ryuo180
        fi
        ;;
    disable)
        rm -f "$base/enabled"
        if [ "$(getprop init.svc.ryuo180)" = running ]; then
            setprop ctl.stop ryuo180
        fi
        pid="$(pidof "$package" || true)"
        case "$pid" in ''|*[!0-9]*) ;; *) kill -TERM "$pid" ;; esac
        am start -W -n "$package/.MainActivity"
        ;;
    remove-startup)
        [ ! -e "$base/enabled" ] || die "Run disable first"
        [ -f "$hook" ] || exit 0
        cmp "$base/ryuo180.rc" "$hook" || die "Unexpected startup hook"
        vendor_device
        open_vendor
        rm "$hook"
        ;;
    *) die "Usage: control.sh {status|install-inactive|enable|disable|remove-startup}" ;;
esac
