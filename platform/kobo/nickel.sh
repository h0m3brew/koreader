#!/bin/sh
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/lib:"

# We don't need to duplicate any of the env setup from rcS, since we will only ever run this to *restart* nickel, and not bootstrap it.
# Meaning we've already got most of the necessary env from nickel itself via both our launcher (fmon/KFMon) and our own startup script.
# NOTE: LD_LIBRARY_PATH is the only late export from rcS we don't siphon in koreader.sh, for obvious reasons ;).
export LD_LIBRARY_PATH="/usr/local/Kobo"

# Reset PWD, and clear up our own custom stuff from the env while we're there, otherwise, USBMS may become very wonky on newer FW...
# shellcheck disable=SC2164
cd /
unset OLDPWD EXT_FONT_DIR TESSDATA_PREFIX FROM_NICKEL STARDICT_DATA_DIR LC_ALL KO_NO_CBB

# Ensures fmon will restart. Note that we don't have to worry about reaping this, nickel kills on-animator.sh on start.
(
    if [ "${PLATFORM}" = "freescale" ] || [ "${PLATFORM}" = "mx50-ntx" ] || [ "${PLATFORM}" = "mx6sl-ntx" ]; then
        usleep 400000
    fi
    /etc/init.d/on-animator.sh
) &

# Make sure we kill the WiFi first, because nickel apparently doesn't like it if it's up... (cf. #1520)
# NOTE: That check is possibly wrong on PLATFORM == freescale (because I don't know if the sdio_wifi_pwr module exists there), but we don't terribly care about that.
if lsmod | grep -q sdio_wifi_pwr; then
    killall restore-wifi-async.sh enable-wifi.sh obtain-ip.sh udhcpc default.script wpa_supplicant 2>/dev/null
    [ "${WIFI_MODULE}" != "8189fs" ] && [ "${WIFI_MODULE}" != "8192es" ] && wlarm_le -i "${INTERFACE}" down
    ifconfig "${INTERFACE}" down
    # NOTE: Kobo's busybox build is weird. rmmod appears to be modprobe in disguise, defaulting to the -r flag...
    #       But since there's currently no modules.dep file being shipped, nor do they include the depmod applet,
    #       go with what the FW is doing, which is rmmod.
    # c.f., #2394?
    usleep 250000
    rmmod "${WIFI_MODULE}"
    usleep 250000
    rmmod sdio_wifi_pwr
fi

# Flush buffers to disk, who knows.
sync

# And finally, simply restart nickel.
# We don't care about horribly legacy stuff, because if people switch between nickel and KOReader in the first place, I assume they're using a decently recent enough FW version.
# Last tested on an H2O & a Forma running FW 4.7.x - 4.12.x
/usr/local/Kobo/hindenburg &
LIBC_FATAL_STDERR_=1 /usr/local/Kobo/nickel -platform kobo -skipFontLoad &
udevadm trigger &

# Handle sdcard
if [ -e "/dev/mmcblk1p1" ]; then
    echo sd add /dev/mmcblk1p1 >>/tmp/nickel-hardware-status &
fi

return 0
