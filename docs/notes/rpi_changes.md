# rPi System Configuration

The operating-system level configuration of an Artisan rPi, outside of
the repo itself: what is set, where, and the exact lines or commands
that set it.  This is the reference for building a fresh card, and the
source for a future setup script in this repo.

Machines are referred to by hostname.  Everything here applies to
rpi4B4A, the current master image.

rpi_setup.sh in the repo root applies all of this to a fresh Raspberry
Pi OS Lite machine, and rpi_build.md describes how a card is made.
Keep this document and that script in agreement.


## Directories

/base and /base_data exist, owned by pi, mode 0777.  /base_data/temp
exists as an EMPTY directory owned by pi; it is the mount point for the
tmpfs below and nothing is ever written to it on the card.


## /etc/environment

    PERLLIB="./:/base:/base/apps/artisan"
    XDG_RUNTIME_DIR="/run/user/1000"

PERLLIB is needed because artisan packages are not fully qualified.
XDG_RUNTIME_DIR is needed for audio to work from a service.


## /etc/sudoers

The first "Defaults ... env_keep" line:

    Defaults:%sudo env_keep+="PERLLIB"


## /boot/firmware/config.txt

After the "# Enable audio" line, for the PiFi DAC+ hat:

    # PRH - added for PiFi DAC+ v2.0
    dtoverlay=hifiberry-dacplus


## /etc/fstab - RAM disk for /base_data/temp

    tmpfs /base_data/temp tmpfs defaults,size=128M,uid=1000,gid=1000,mode=0755,nosuid,nodev 0 0

Every Pub-based service (artisan, fileServer, myIOTServer) keeps only a
log and a pid file under /base_data/temp/<app>, and creates its own
subfolder at startup.  With the parent mounted as a tmpfs none of them
write to the SD card during normal operation.  Logs do not survive a
reboot.  128 MB is far more than needed; 64 would do.

The artisan service runs as pi (uid 1000), is Type=forking, and names
its PIDFile inside its subfolder, so the mount is owned by pi.  fstab
mounts are done at local-fs.target, before any service starts.

To apply on a running Pi:

    sudo systemctl stop artisan
    sudo systemctl stop fileServer
    sudo rm -rf /base_data/temp/*
    echo 'tmpfs /base_data/temp tmpfs defaults,size=128M,uid=1000,gid=1000,mode=0755,nosuid,nodev 0 0' | sudo tee -a /etc/fstab
    sudo systemctl daemon-reload
    sudo mount /base_data/temp
    sudo systemctl start artisan
    sudo systemctl start fileServer

To verify after a reboot:

    mount | grep base_data
    systemctl status artisan --no-pager | head -3
    ls -la /base_data/temp/artisan      # artisan.log and artisan.pid

To remove:

    sudo systemctl stop artisan
    sudo systemctl stop fileServer
    sudo umount /base_data/temp
    sudo sed -i '\|/base_data/temp|d' /etc/fstab
    sudo systemctl daemon-reload
    sudo systemctl start artisan
    sudo systemctl start fileServer


## Packages

Perl modules: /base/Pub/setup_rpi_perl.sh.  Plus:

    sudo apt-get install mpg123


## Services

artisan: per the comments in artisan.service.

    sudo cp /base/apps/artisan/artisan.service /usr/lib/systemd/system
    sudo systemctl enable artisan.service

The installed unit is a copy.  The webUI update function pulls the repo
but does not recopy it; after changing artisan.service, recopy it and
run "sudo systemctl daemon-reload".

fileServer: unit name "fileServer", runs as root, per the comments in
/base/Pub/FS/fileserver.service.

myIOTServer: installed but not enabled on this image.


## Hostname and IP

The library and renderer uuid is ArtisanPerl-<hostname>, so every Pi on
the LAN needs a distinct hostname, and each has a reserved IP in the
THX59 router (rpi4B4A = 10.237.50.156).  To rename a cloned card:

    sudo systemctl stop artisan
    sudo hostnamectl set-hostname NEWNAME
    sudo sed -i 's/OLDNAME/NEWNAME/g' /etc/hosts
    rm /media/pi/SanDisk/mp3s/_data/playlists.db
    sudo reboot

playlists.db records carry the uuid at creation and are never refreshed,
so it is removed and Artisan rebuilds it on the next start.


## /etc/fstab - mp3 stick

    LABEL=SanDisk /media/pi/SanDisk exfat defaults,nofail,uid=1000,gid=1000,x-systemd.device-timeout=10 0 0

The mp3 path is /media/pi/SanDisk/mp3s (artisanUtils.pm), so the stick's
label must be SanDisk and it is exFAT.  Mounting it from fstab puts it in
place at local-fs, a few seconds after power, instead of when the desktop
session's automounter gets to it.  nofail: a missing or unmountable stick
does not stop the boot; artisan then waits and restarts itself until one
appears.  The mount point must exist on the card and is owned by pi:

    sudo mkdir -p /media/pi/SanDisk
    sudo chown pi:pi /media/pi/SanDisk

(The desktop automounter deletes its own mount points on unmount, so this
directory has to be created by hand once the fstab line is in.)

Startup budget after this, on a cold boot: kernel ~4 s, stick mounted and
artisan started ~9 s, Wi-Fi association ~7 s more, then the library scan.
Artisan cannot serve before it has an IP address.
