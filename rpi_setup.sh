#!/bin/bash
#-------------------------------------------------------------------
# rpi_setup.sh - make a Raspberry Pi OS Lite machine into an Artisan Pi
#-------------------------------------------------------------------
# Idempotent: every step checks before it changes anything, prints
# what it changed, and is safe to rerun at any time.  Run as root
# (it re-executes itself under sudo).  This script is the executable
# form of docs/notes/rpi_changes.md; keep the two in agreement.
#
# The card is expected to have been made by rpi_card.pl, which uses
# cloud-init (user-data on the boot partition) to set the hostname,
# the pi user, SSH, Wi-Fi, locale and timezone, and by default embeds
# a copy of this script and runs it on the first boot.  Nothing here
# depends on that: it can equally be scp'd to a fresh Lite machine
# and run by hand.
#
#   sudo ./rpi_setup.sh [--with-myiot] [--reboot]
#
#   --with-myiot   also clone and enable myIOTServer (unproven)
#   --reboot       reboot at the end if any step needed it
#
# Contains no credentials.  Repos are public; the pi user already
# exists.  Log of an unattended first-boot run: /var/log/rpi_setup.log

set -u

PI_USER=pi
PI_UID=1000
BASE=/base
DATA=/base_data
STICK_LABEL=SanDisk
STICK_MOUNT=/media/pi/$STICK_LABEL
CONFIG_TXT=/boot/firmware/config.txt
GITHUB=https://github.com/phorton1

WITH_MYIOT=0
DO_REBOOT=0
for arg in "$@"; do
    case "$arg" in
        --with-myiot) WITH_MYIOT=1 ;;
        --reboot)     DO_REBOOT=1 ;;
        *) echo "unknown argument: $arg"; exit 1 ;;
    esac
done

if [ "$(id -u)" != 0 ]; then
    exec sudo "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive
NEED_REBOOT=0
CHANGES=0

changed()
{
    CHANGES=$((CHANGES + 1))
    echo "CHANGED: $*"
}

ok()
{
    echo "ok:      $*"
}

# ensure_line FILE LINE - append LINE to FILE if not present verbatim
ensure_line()
{
    local file="$1" line="$2"
    if grep -qxF -- "$line" "$file" 2>/dev/null; then
        ok "$file has: $line"
    else
        echo "$line" >> "$file"
        changed "$file += $line"
        NEED_REBOOT=1
    fi
}

# ensure_dir DIR MODE - create DIR owned by pi
ensure_dir()
{
    local dir="$1" mode="$2"
    if [ -d "$dir" ]; then
        ok "dir $dir"
    else
        mkdir -p "$dir"
        changed "mkdir $dir"
    fi
    chown $PI_USER:$PI_USER "$dir"
    chmod "$mode" "$dir"
}

# wait_network - block until a package host resolves (first boot on Wi-Fi)
wait_network()
{
    local i
    for i in $(seq 1 60); do
        getent hosts deb.debian.org >/dev/null 2>&1 && return 0
        [ "$i" = 1 ] && echo "waiting for the network ..."
        sleep 2
    done
    echo "ERROR: no network after 120 s"
    return 1
}

# apt_ensure PKG... - install whichever of PKG... are missing, in one call
apt_ensure()
{
    local missing=() pkg
    for pkg in "$@"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            ok "package $pkg"
        else
            missing+=("$pkg")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        wait_network || return 1
        if [ "${APT_UPDATED:-0}" = 0 ]; then
            apt-get update -q || return 1
            APT_UPDATED=1
        fi
        apt-get install -y -q "${missing[@]}" || return 1
        changed "installed ${missing[*]}"
    fi
}

# clone_repo URL DIR - clone as pi if DIR is not already a git repo
clone_repo()
{
    local url="$1" dir="$2"
    if [ -d "$dir/.git" ]; then
        ok "repo $dir"
    else
        wait_network || return 1
        sudo -u $PI_USER git clone -q "$url" "$dir" || return 1
        changed "cloned $url -> $dir"
    fi
}

# install_unit SRC NAME - copy a unit file into systemd if it differs, and enable it
install_unit()
{
    local src="$1" name="$2" dst="/usr/lib/systemd/system/$2"
    if [ ! -f "$src" ]; then
        echo "ERROR: unit source $src does not exist"
        return 1
    fi
    if cmp -s "$src" "$dst"; then
        ok "unit $name"
    else
        cp "$src" "$dst" || return 1
        systemctl daemon-reload
        changed "unit $name installed from $src"
    fi
    if systemctl is-enabled -q "$name" 2>/dev/null; then
        ok "unit $name enabled"
    elif systemctl enable -q "$name"; then
        changed "unit $name enabled"
    else
        echo "ERROR: could not enable $name"
        return 1
    fi
}


echo "===== rpi_setup.sh on $(hostname) $(date '+%Y-%m-%d %H:%M:%S')"

#-------------------------------------------------------------------
# 1. directories
#-------------------------------------------------------------------

ensure_dir $BASE          0777
ensure_dir $BASE/apps     0777
ensure_dir $DATA          0777
ensure_dir $DATA/temp     0755
ensure_dir $STICK_MOUNT   0755

#-------------------------------------------------------------------
# 2. /etc/environment and sudoers
#-------------------------------------------------------------------

ENV=/etc/environment
if grep -q '^PERLLIB=' $ENV 2>/dev/null && ! grep -qxF 'PERLLIB="./:/base:/base/apps/artisan"' $ENV; then
    sed -i '/^PERLLIB=/d' $ENV
    changed "$ENV removed stale PERLLIB line"
fi
ensure_line $ENV 'PERLLIB="./:/base:/base/apps/artisan"'
ensure_line $ENV 'XDG_RUNTIME_DIR="/run/user/1000"'

SUDOERS_D=/etc/sudoers.d/010_perllib
if [ -f $SUDOERS_D ]; then
    ok "sudoers $SUDOERS_D"
else
    echo 'Defaults env_keep += "PERLLIB"' > $SUDOERS_D
    chmod 0440 $SUDOERS_D
    if visudo -cf $SUDOERS_D >/dev/null; then
        changed "sudoers $SUDOERS_D"
    else
        rm -f $SUDOERS_D
        echo "ERROR: visudo rejected $SUDOERS_D"
    fi
fi

#-------------------------------------------------------------------
# 3. PiFi DAC+ hat: overlay, and pin it as the ALSA default
#-------------------------------------------------------------------

if grep -q '^dtoverlay=hifiberry-dacplus' $CONFIG_TXT; then
    ok "$CONFIG_TXT hifiberry-dacplus overlay"
else
    printf '\n# PRH - PiFi DAC+ v2.0 (rpi_setup.sh)\ndtoverlay=hifiberry-dacplus\n' >> $CONFIG_TXT
    changed "$CONFIG_TXT += dtoverlay=hifiberry-dacplus"
    NEED_REBOOT=1
fi

ASOUND=/etc/asound.conf
if grep -q 'sndrpihifiberry' $ASOUND 2>/dev/null; then
    ok "$ASOUND default = hat"
else
    cat > $ASOUND <<'EOF'
# rpi_setup.sh - the PiFi DAC+ hat is the only audio output.
# Pin it as the ALSA default so mpg123 needs no device argument.
pcm.!default {
    type plug
    slave.pcm "hw:sndrpihifiberry"
}
ctl.!default {
    type hw
    card sndrpihifiberry
}
EOF
    changed "$ASOUND default = hat"
fi

#-------------------------------------------------------------------
# 4. fstab: RAM disk for /base_data/temp, mp3 stick by label
#-------------------------------------------------------------------

ensure_line /etc/fstab "tmpfs $DATA/temp tmpfs defaults,size=128M,uid=$PI_UID,gid=$PI_UID,mode=0755,nosuid,nodev 0 0"
ensure_line /etc/fstab "LABEL=$STICK_LABEL $STICK_MOUNT exfat defaults,nofail,uid=$PI_UID,gid=$PI_UID,x-systemd.device-timeout=10 0 0"
systemctl daemon-reload
if mountpoint -q $DATA/temp; then
    ok "tmpfs mounted on $DATA/temp"
else
    mount $DATA/temp && changed "mounted tmpfs on $DATA/temp"
fi
if mountpoint -q $STICK_MOUNT; then
    ok "stick mounted on $STICK_MOUNT"
elif [ -e /dev/disk/by-label/$STICK_LABEL ]; then
    mount $STICK_MOUNT && changed "mounted stick on $STICK_MOUNT"
else
    echo "note:    no stick labeled $STICK_LABEL present (fine; nofail)"
fi

#-------------------------------------------------------------------
# 5. NetworkManager: keep the real MAC so the router reservation holds
#-------------------------------------------------------------------

NM_CONF=/etc/NetworkManager/conf.d/100-disable_mac_randomization.conf
if [ -f $NM_CONF ]; then
    ok "$NM_CONF"
else
    cat > $NM_CONF <<'EOF'
[device]
wifi.scan-rand-mac-address=no

[connection-mac-randomization]
wifi.cloned-mac-address=permanent
EOF
    changed "$NM_CONF"
    NEED_REBOOT=1
fi

#-------------------------------------------------------------------
# 6. packages, repos, Perl modules
#-------------------------------------------------------------------

apt_ensure git mpg123 alsa-utils exfatprogs || exit 1

clone_repo $GITHUB/base-Pub                           $BASE/Pub                        || exit 1
clone_repo $GITHUB/base-apps-artisan                  $BASE/apps/artisan               || exit 1
clone_repo $GITHUB/base-apps-artisan-webUI-standard   $BASE/apps/artisan/webUI/standard || exit 1
if [ $WITH_MYIOT = 1 ]; then
    clone_repo $GITHUB/base-apps-myIOTServer          $BASE/apps/myIOTServer           || exit 1
fi

# The Perl module list lives in Pub; install it non-interactively.
PERL_PKGS=$(grep -o 'lib[a-z0-9-]*-perl' $BASE/Pub/setup_rpi_perl.sh | sort -u)
apt_ensure $PERL_PKGS || exit 1

for f in $BASE/apps/artisan/artisan.pm $BASE/Pub/FS/fileServer.pm $BASE/apps/myIOTServer/myIOTServer.pm; do
    [ -f "$f" ] && [ ! -x "$f" ] && chmod +x "$f" && changed "chmod +x $f"
done

#-------------------------------------------------------------------
# 7. services
#-------------------------------------------------------------------

FIRST_INSTALL=0
[ -f /usr/lib/systemd/system/artisan.service ] || FIRST_INSTALL=1

install_unit $BASE/apps/artisan/artisan.service   artisan.service      || exit 1
install_unit $BASE/Pub/FS/fileServer.service      fileServer.service   || exit 1
if [ $WITH_MYIOT = 1 ]; then
    install_unit $BASE/apps/myIOTServer/myIOTServer.service myIOTServer.service || exit 1
fi

#-------------------------------------------------------------------
# 8. a stick that came from another Pi carries that Pi's uuid.
#    Only on the first install: after that the file is this Pi's own,
#    and Artisan may be running on it.
#-------------------------------------------------------------------

PLDB=$STICK_MOUNT/mp3s/_data/playlists.db
if [ $FIRST_INSTALL = 1 ] && [ -f $PLDB ]; then
    rm -f $PLDB
    changed "removed $PLDB (uuid is the hostname; Artisan rebuilds it)"
fi

#-------------------------------------------------------------------
# done
#-------------------------------------------------------------------

echo "===== rpi_setup.sh finished: $CHANGES change(s), reboot needed: $NEED_REBOOT"
if [ $NEED_REBOOT = 1 ] && [ $DO_REBOOT = 1 ]; then
    echo "rebooting"
    sync
    reboot
fi
exit 0
