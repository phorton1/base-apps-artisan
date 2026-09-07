# Building an Artisan rPi

How a new Artisan Raspberry Pi is made from a blank SD card.  The
system-level result is described in rpi_changes.md; this document is
the process.  Two scripts in the repo root do the work:

    rpi_card.pl    on the laptop: writes the OS image and the first-boot
                   configuration to the card
    rpi_setup.sh   on the Pi: turns Raspberry Pi OS Lite into an Artisan
                   Pi; idempotent, safe to rerun at any time

No credentials, private paths or locale values are in the repo.  They
are all arguments to rpi_card.pl; it has no defaults for them.


## OS image

Raspberry Pi OS Lite, 64-bit, Trixie (Debian 13) or later, from
https://downloads.raspberrypi.com/raspios_lite_arm64/images/ (the
.img.xz and its .sha256; check the hash).  Lite has no desktop, no
automounter and no PulseAudio; the stick mounts from fstab and mpg123
talks to ALSA.

The same image boots a 4B and a 5.  A card written for one board boots on
the other; nothing in the build is board-specific.


## First boot: cloud-init

Trixie images are configured on first boot by cloud-init from three files
on the FAT boot partition (the part Windows can see):

    user-data        hostname, timezone, locale, the pi user with its
                     password hash and SSH key, SSH enabled, and an
                     embedded copy of rpi_setup.sh that runs at the end
                     of the first boot and reboots
    network-config   eth0 by DHCP, wlan0 by DHCP with every --wifi access
                     point at equal priority, regulatory domain PA
    meta-data        instance id (the hostname)

Raspberry Pi Imager 2.0 or later writes the same three files from its
customisation dialog.  rpi_card.pl writes them itself so that the whole
card is made from one command line, with the setup script embedded.


## Without rpi_card.pl

rpi_card.pl is Windows-only (it uses PowerShell to find the disk).  On
any other machine, or by hand, the same card is made in three steps:

1.  Write the Lite image to the card.
2.  On the boot partition, replace user-data and network-config.  Leave
    the image's meta-data alone.  A minimal user-data:

        #cloud-config
        hostname: HOSTNAME
        manage_etc_hosts: true
        timezone: ZONE
        users:
          - name: pi
            groups: users,adm,dialout,audio,netdev,video,plugdev,gpio,sudo
            shell: /bin/bash
            lock_passwd: false
            plain_text_passwd: PASSWORD
            sudo: ALL=(ALL) NOPASSWD:ALL
        enable_ssh: true
        ssh_pwauth: true

    and network-config:

        network:
          version: 2
          renderer: NetworkManager
          ethernets:
            eth0:
              dhcp4: true
              optional: true
          wifis:
            wlan0:
              dhcp4: true
              optional: true
              regulatory-domain: "CC"
              access-points:
                "SSID":
                  password: "PASSWORD"

    The "#cloud-config" first line is mandatory.  Both files must have
    LF line endings.  Imager 2.0's customisation dialog produces the
    same result.
3.  Boot the Pi, ssh in as pi, and run rpi_setup.sh as described below.
    Or, for a fully manual build, follow rpi_changes.md line by line;
    the script and that document say the same things.

Assumptions baked into the script that a different installation would
change: the mp3 library is on a USB stick labeled SanDisk, formatted
exFAT, with the music under mp3s/ (the path is in artisanUtils.pm); the
audio output is a HiFiBerry DAC+ compatible hat; the user is pi with
uid 1000.


## Making a card

1.  Put a blank card in a reader.  No formatting is needed; the image
    replaces everything on it.
2.  Write the image with the Raspberry Pi Imager GUI: Choose Device is
    only a filter and can be skipped; Choose OS, "Use custom", the
    .img.xz; Choose Storage, the card reader; Write.  Answer NO to OS
    customisation: Imager 1.8 and 1.9 write a format that Trixie does
    not read, and the next step writes what it does read.  Deny the
    Windows location prompt.  Imager ejects the card when it finishes;
    pull it and reinsert it so that the bootfs partition gets a drive
    letter (cancel any offer to format the other partition).
3.  From a shell in the repo, with any Perl 5.12 or later:

        perl rpi_card.pl --host HOSTNAME --drive X \
            --skip-flash --image PATH.img.xz --pipw PASSWORD \
            --wifi SSID=PASSWORD --wifi SSID=PASSWORD \
            --country CC --tz ZONE --sshkey KEYFILE

    The hostname is the Artisan uuid, so it must be unique on the LAN.
    KEYFILE is the laptop's private SSH key; KEYFILE.pub goes onto the
    card.  One key pair serves every Pi.  --no-sshkey instead gives
    password-only ssh.  The script refuses disk 0, any non-USB/SD disk,
    and anything over 256 GB, then writes the cloud-init files.

    Without --skip-flash the script runs Imager itself in --cli mode.
    That needs elevation (one UAC prompt), shows no progress, and is not
    the normal path.
4.  Eject the card, put it in the Pi with the mp3 stick, power on.
    First boot: cloud-init configures the system, rpi_setup.sh installs
    packages, clones the repos and services, and reboots.  On Wi-Fi the
    first card took about five minutes from power-on to Artisan
    answering on the second boot.
5.  From the laptop:

        perl rpi_card.pl --check HOSTNAME --sshkey KEYFILE

    reports hostname, IP, mounts, services, ALSA cards and whether the
    HTTP server answers on port 8091.
6.  Reserve the Pi's IP in the router.  Browsers store Artisan state per
    IP:port, and the head unit is pointed at an address, not a name.

Options: --out DIR writes the cloud-init files to a folder instead of a
card for inspection; --skip-flash rewrites only the boot files on an
already written card; --no-bootstrap leaves rpi_setup.sh out, giving a
plain ssh-reachable Lite machine; --with-myiot adds myIOTServer.


## rpi_setup.sh on its own

    scp rpi_setup.sh pi@HOSTNAME.local:
    ssh pi@HOSTNAME.local sudo bash rpi_setup.sh --reboot

does the same on any Lite machine that already has a pi user and a
network.  It needs nothing from this repo beforehand; it clones the
repos itself.  Every step prints "ok:" or "CHANGED:" and the script ends with
a count.  The first-boot run logs to /var/log/rpi_setup.log.

The steps, in order: directories; /etc/environment and a sudoers
drop-in; the hifiberry-dacplus overlay and /etc/asound.conf pinning the
hat as the ALSA default; the tmpfs and stick fstab lines; a
NetworkManager drop-in that keeps the real Wi-Fi MAC so the router
reservation holds; git, mpg123, alsa-utils, exfatprogs; the three repos
(Pub, artisan, artisan/webUI/standard) cloned as pi into /base; the Perl
modules listed in /base/Pub/setup_rpi_perl.sh; the artisan and
fileServer units; and removal of a playlists.db carried over on the
stick from another Pi.
