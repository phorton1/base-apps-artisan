# rpi_build.md - Building an Artisan and/or myIOTServer rPi

This document describes how the operating system SD card on an rPI
is built systematically, thus making the SD card building process
repeatable and deterministic.  This process is focused around two
scripts - one perl script running on the laptop, and another shell script
running on the pi, either at its first boot, or by explicit invocation.

Theoretically this process can be run by Patrick without help, but in practice
Claude greatly facilitates this process.  Even with Claude's help, Patrick is still
required for several steps in the process.


## Outline of Nominal Process

- an **SDCard is burned** with an rPI os image from the laptop.
  This theoretically can be accomplished from the *rpi_card.pl* script,
  but in practice is performed manually by Patrick using the **rPI disk imager**,
  and produces a laptop readable bootfs FAT partition, and a non-laptop readable
  partition that contains the actual OS partition.
- the **rpi_card.pl** script is run to put some files in the bootfs
  FAT partition from the laptop.  Those files configure things like the
  pi password, network configuration, and so on, and importantly contain
  the contents of the second shell script, *rpi_setup.sh* along with
  commands to run it, optionally, on the first boot.
- The sd card is moved from the laptop to the target rPi, where it is booted.
  Since it will be running *artisan* it is booted with a prepared **USB Stick**
  named "SanDisk" and populated with the **mp3s library contents**.
- Upon booting the **rpi_setup.sh** script is run, which does the significant
  work of setting up many configuration files, installing packages and perl
  modules via *apt install* and so on, cloning the artisan and/or myIOTServer source code from
  github, installing and starting the services.


In this nominal process, after the first boot has completed, if all goes well
the **artisan and/or myIOTServer services** will be running and the system
is functional.  Usually, by convention, some verification steps are typically
run to confirm the whole process went well.

No credentials, private paths or locale values are in the repo.  They
are all arguments to rpi_card.pl; it has no defaults for them.



## OS image

As of this writing we are using Raspberry Pi OS Lite, 64-bit, Trixie (Debian 13) or later
as found at https://downloads.raspberrypi.com/raspios_lite_arm64/images/ and exists on
this machine at

**C:\zip\_rPi\raspian_images\2026-06-18-raspios-trixie-arm64-lite.img**

The same image boots a rPi 4B and an rPi 5.  A card written for one board boots on
the other; nothing in the build is board-specific, though we are currently using
rpi4B's with either 2GB or 4GB of RAM.

- insert a **16GB** SD card into a card reader and insert it into a USB port
  on the laptop.
- run the **rPi Disk Imager** currently on this machine.  Say "yes" to the
  *UAC prompt*.
- **Choose OS**, scroll to the end and pick "Use custom" to select the
  above raspian image.
- **Select the SD Card** on the card reader, typically the **D:** drive.
- Press the **Write** button.
- Say **no to customization**.
- **Deny the Windows location prompt**, if any.

The write, with a verify, will take **20-30 minutes**.  When it finishes
the rPi Disk Imager program ejects the card, so you must remove and re-insert
the card reader for the subsequent steps.

**You should see the bootfs partition in Windows Explorer on the laptop**
at some drive letter.  Cancel any offers to format the other partition.




## rpi_card.pl

The **rpi_card.pl** script has quite a few parameters, including the theoretical
ability to flash the OS image to a SD card. Please see it, in this
repo, for more information about the specific parameters.  However, in
essence, what it does is to **write 3 files** to the laptop readable bootfs
FAT partition.

These three files are used automatically by the Trixie raspian image to
effect a one time configuration/installation process that is confusingly
called *cloud init*, although it has nothing to do with "the cloud", per-se.


### file1: **meta-data**

The file **meta-data** drives the *one time* configuration process.
It contains two lines:

- **instance-id** - an arbitrary identifier
- **local-hostname** - the name given to the rPi

A change to the instance-id (i.e. versus a non-existent previous run)
causes the *one time* configuration process to run, thus effecting
a change of local_hostname, as well as causing the other two files
to be processed.


### file2: **network-config**

The **network-config** file configures the network and one or
more equal priority Wifi **SSIDs** and **passwords**.

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


### file3: **user-data**

The **user-data** file written to the bootfs FAT partition is
the workhorse of the configuration process.  Not only does it
contain the bulk of the **configuration options** like the
hostname, timezone, pi user and password, and doing things
like **enabling ssh**:

```yaml
#cloud-config
hostname: HOSTNAME
manage_etc_hosts: true
timezone: ZONE
users:
  - name: pi
    groups: users,adm,dialout,audio,netdev,video,plugdev,cdrom,games,input,gpio,spi,i2c,render,sudo
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: PASSWORD
    sudo: ALL=(ALL) NOPASSWD:ALL
enable_ssh: true
ssh_pwauth: true
```

In the nominal process **user-data** also contains the
entire *rpi_setup.sh* script and *invokes it* (depending
on rpi_card.pl command line options) in sections like this:

``` yaml
  write_files:
    - path: /usr/local/sbin/rpi_setup.sh
      permissions: "0755"
      owner: root:root
      content: |
        #!/bin/bash
        ...the entire contents of rpi_setup.sh, every line indented
        six spaces under "content: |" so YAML reads it as one literal
        block, and strips that indent back off when it writes the file...

  runcmd:
    - [ sh, -c, "/usr/local/sbin/rpi_setup.sh > /var/log/rpi_setup.log 2>&1" ]

  power_state:
    mode: reboot
    message: rpi_card.pl first boot complete
    condition: true
```


## PATRICK TO HERE


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
            groups: users,adm,dialout,audio,netdev,video,plugdev,cdrom,games,input,gpio,spi,i2c,render,sudo
            shell: /bin/bash
            lock_passwd: false
            plain_text_passwd: PASSWORD
            sudo: ALL=(ALL) NOPASSWD:ALL
        enable_ssh: true
        ssh_pwauth: true

    and network-config:







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








Lite has no desktop, no automounter and no PulseAudio, so the stick mounts from
fstab and mpg123 talks to ALSA.







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
plain ssh-reachable Lite machine; --with-myiot passes --with-myiot on to
the embedded rpi_setup.sh.  Note that myIOTServer also needs private
files that rpi_card.pl does not place (see "myIOTServer" below), so in
practice myIOTServer is added to an already-running Pi rather than baked
into a fresh card.


## rpi_setup.sh on its own

    scp rpi_setup.sh pi@HOSTNAME.local:
    ssh pi@HOSTNAME.local sudo bash rpi_setup.sh --reboot

does the same on any Lite machine that already has a pi user and a
network.  It needs nothing from this repo beforehand; it clones the
repos itself.  Every step prints "ok:" or "CHANGED:" and the script ends with
a count.  The first-boot run logs to /var/log/rpi_setup.log.

The script's own header comment block is the authoritative usage; it
lists the flags and what each does.  The flags are: --reboot (reboot at
the end if a step needed it); --with-myiot (also install myIOTServer,
see below); and --files DIR (place private files from DIR, see below).
With no flags the OS, the repos, and the artisan and fileServer services
are set up and nothing private is copied.

The steps, in order: directories (including /base_data/data); /etc/environment
and a sudoers drop-in; the hifiberry-dacplus overlay and /etc/asound.conf
pinning the hat as the ALSA default; the tmpfs and stick fstab lines; a
NetworkManager drop-in that keeps the real Wi-Fi MAC so the router
reservation holds; git, mpg123, alsa-utils, exfatprogs; the repos (Pub,
artisan, artisan/webUI/standard, and myIOTServer with its submodules
under --with-myiot) cloned as pi into /base; the Perl modules listed in
/base/Pub/setup_rpi_perl.sh; under --files, the private files placed into
/base_data (below); the ssh client config for any forwarding host named
in the placed prefs (below); the artisan, fileServer, and (under
--with-myiot) myIOTServer units; and removal of a playlists.db carried
over on the stick from another Pi.


## myIOTServer (--with-myiot) and the private files

myIOTServer is the optional IOT bridge: an HTTPS and secure-websocket
server on port 6902 that discovers the boat's ESP32 devices by SSDP and
proxies them to a browser.  It is not part of a plain Artisan Pi, and
turning it on needs files that are deliberately not in any repo.  For
that reason it is normally added to an already-running Pi, not a fresh
card.

Those private files live on the laptop under /base_data and are copied
to the Pi, not generated:

    /base_data/_ssl/            certs, keys, PubCryptKey.txt, the tunnel
                                ssh key.  Identical on every machine;
                                copy as-is.
    /base_data/data/myIOTServer/users.txt   the HTTP Basic-auth users.
                                Identical on every machine; copy as-is.
    /base_data/data/myIOTServer/myIOTServer.prefs
    /base_data/data/fileServer/fileServer.prefs
                                your laptop prefs with this Pi's forward
                                ports set (the per-machine port map is in
                                PORTS_IN_USE.xlsx, not in the repo).

The mechanism is --files DIR: scp a copy of those /base_data pieces to
the Pi, then run the script with --files pointing at it.  The script
copies the _ssl files (replacing any that differ) and seeds the prefs
and users.txt (copied only if absent, so a rerun never clobbers a value
a running service rewrote, such as a forward toggled on from the admin
page).  --with-myiot then refuses to enable the service unless the
required files are present.

Because the reverse tunnel logs in to an old sshd, the script also writes,
for both the pi and root users (myIOTServer forwards as pi, the fileServer
as root), a known_hosts entry and an ~/.ssh/config stanza allowing SHA-1
RSA signatures for the forwarding host named in the prefs.  With SSL
turned on in fileServer.prefs the fileServer moves to port 5873 and
verifies client certificates against the phorton CA; without the _ssl
files it stays plain on 5872.

The private-files placement and the forward-port convention are estate
concerns that outgrow this repo; they live here as a documented manual
step until a private estate layer owns them.
