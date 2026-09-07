#!/usr/bin/perl
#-------------------------------------------------------------------
# rpi_card.pl - make a self-installing Artisan SD card on Windows
#-------------------------------------------------------------------
# Writes a Raspberry Pi OS Lite (Trixie or later) image to a physical
# disk with Raspberry Pi Imager in CLI mode, then puts cloud-init
# files on the FAT boot partition so the first boot sets the hostname,
# the pi user, SSH, Wi-Fi, locale and timezone, and (by default) runs
# an embedded copy of rpi_setup.sh, then reboots.  After that the Pi is
# ssh-reachable as HOST.local and running Artisan.
#
# Plain Perl, no Pub dependency; run from git-bash:
#
#   /c/Perl/bin/perl.exe rpi_card.pl --host NAME --drive X --image PATH \
#       --pipw PASSWORD --wifi SSID=PASSWORD --wifi SSID=PASSWORD \
#       --country CC --tz ZONE --sshkey FILE
#
#   --host NAME        hostname; also the Artisan uuid, so LAN-unique
#   --drive X | --disk N   the card, by drive letter or physical disk number
#   --image PATH       the raspios-*-lite.img.xz to write
#   --pipw PW          password for user pi
#   --wifi SSID=PW     repeatable; all access points get equal priority
#   --country CC       Wi-Fi regulatory domain
#   --tz ZONE          timezone, e.g. America/Panama
#   --sshkey FILE      private key file whose FILE.pub the Pi will accept;
#                      also used by --check.  --no-sshkey for password only
#   --no-bootstrap     do not embed and run rpi_setup.sh on first boot
#   --with-myiot       pass --with-myiot to the embedded rpi_setup.sh
#   --skip-flash       card already written; only (re)write the boot files
#   --out DIR          no card work; write the cloud-init files to DIR instead
#   --check HOST       no card work; ssh to HOST.local with --sshkey and
#                      report its state
#
# Credentials, paths and locale are ARGUMENTS.  This script holds no
# defaults for them and nothing in this repo holds a credential.
#
# Safety: the target must be a USB or SD bus disk under 256 GB and never
# disk 0.  Imager needs elevation to open a physical disk, so Windows
# shows one UAC prompt for the flash step.

use strict;
use warnings;
use Getopt::Long;
use File::Basename;
use File::Spec;

my $IMAGER = 'C:\Program Files (x86)\Raspberry Pi Imager\rpi-imager.exe';
my $SETUP_SH = File::Spec->catfile(dirname(File::Spec->rel2abs($0)), 'rpi_setup.sh');
my $ARTISAN_PORT = 8091;

my ($host, $drive, $disk, $image, $pipw, @wifi, $country, $tz, $sshkey, $check, $out);
my $no_sshkey = 0;
my $no_bootstrap = 0;
my $with_myiot = 0;
my $skip_flash = 0;

GetOptions(
    'host=s'       => \$host,
    'drive=s'      => \$drive,
    'disk=i'       => \$disk,
    'image=s'      => \$image,
    'pipw=s'       => \$pipw,
    'wifi=s'       => \@wifi,
    'country=s'    => \$country,
    'tz=s'         => \$tz,
    'sshkey=s'     => \$sshkey,
    'no-sshkey'    => \$no_sshkey,
    'no-bootstrap' => \$no_bootstrap,
    'with-myiot'   => \$with_myiot,
    'skip-flash'   => \$skip_flash,
    'check=s'      => \$check,
    'out=s'        => \$out,
) or die "bad arguments\n";

die "--sshkey FILE or --no-sshkey is required\n" if !$sshkey && !$no_sshkey;
die "private key not found: $sshkey\n" if $sshkey && !-f $sshkey;
die "public key not found: $sshkey.pub\n" if $sshkey && !-f "$sshkey.pub";

exit check_pi($check) if $check;

die "--host is required\n" if !$host;
die "--host must be a plain hostname\n" if $host !~ /^[A-Za-z0-9][A-Za-z0-9-]*$/;
die "--image is required\n" if !$image;
die "image not found: $image\n" if !-f $image;
die "--pipw is required\n" if !$pipw;
die "--country is required\n" if !$country;
die "--tz is required\n" if !$tz;
die "--drive or --disk is required\n" if !$out && !defined $drive && !defined $disk;

my $pubkey = '';
if ($sshkey)
{
    open my $fh, '<', "$sshkey.pub" or die "$sshkey.pub: $!\n";
    ($pubkey) = grep { /\S/ } <$fh>;
    close $fh;
    chomp $pubkey;
}

my $boot = $out ? $out : prepare_card();
mkdir $boot if $out && !-d $out;

sub prepare_card
    # vet the disk, flash it, and return the boot partition drive
{
    #-------------------------------------------------------------------
    # 1. resolve and vet the target disk
    #-------------------------------------------------------------------

    if (defined $drive)
    {
        $drive = uc substr($drive, 0, 1);
        my $n = ps("(Get-Partition -DriveLetter $drive -ErrorAction Stop).DiskNumber");
        die "drive $drive: is not a partition on a disk\n" if $n !~ /^\d+$/;
        $disk = $n;
    }
    die "refusing disk 0 (the system disk)\n" if $disk == 0;

    my $info = ps("\$d = Get-Disk -Number $disk -ErrorAction Stop; "
        . "'{0}|{1}|{2}|{3}|{4}' -f \$d.BusType, \$d.Size, \$d.FriendlyName, \$d.IsSystem, \$d.IsBoot");
    my ($bus, $size, $name, $is_system, $is_boot) = split /\|/, $info;
    die "cannot read disk $disk: $info\n" if !defined $size || $size !~ /^\d+$/;
    my $gb = sprintf '%.1f', $size / 1e9;
    print "target: disk $disk  $name  $gb GB  bus $bus\n";
    die "refusing: bus type $bus is not USB/SD/MMC\n" if $bus !~ /^(USB|SD|MMC)$/;
    die "refusing: $gb GB is too big for a card\n" if $size > 256e9;
    die "refusing: system or boot disk\n" if $is_system =~ /true/i || $is_boot =~ /true/i;

    #-------------------------------------------------------------------
    # 2. flash (elevated Imager, CLI mode, verify on)
    #-------------------------------------------------------------------

    if ($skip_flash)
    {
        print "skipping flash\n";
    }
    else
    {
        die "imager not found: $IMAGER\n" if !-f $IMAGER;
        print "flashing $image\n";
        print "  -> \\\\.\\PhysicalDrive$disk  (answer the UAC prompt; several minutes)\n";
        my $rslt = ps("\$p = Start-Process -FilePath '$IMAGER' "
            . "-ArgumentList '--cli','$image','\\\\.\\PhysicalDrive$disk' "
            . "-Verb RunAs -Wait -PassThru; \$p.ExitCode");
        die "imager exit code: $rslt\n" if $rslt ne '0';
        print "flash complete and verified\n";
    }

    #-------------------------------------------------------------------
    # 3. find the boot partition
    #-------------------------------------------------------------------

    my $boot;  # e.g. "E:"
    for my $try (1 .. 30)
    {
        my $letter = ps("(Get-Partition -DiskNumber $disk | Get-Volume | "
            . "Where-Object { \$_.FileSystemLabel -eq 'bootfs' -and \$_.DriveLetter }).DriveLetter");
        if ($letter =~ /^[A-Z]$/i)
        {
            $boot = uc($letter) . ':';
            last;
        }
        sleep 2;
    }
    if (!$boot)
    {
        # Windows did not hand out a letter; ask it to (needs elevation)
        ps("Start-Process powershell -Verb RunAs -Wait -ArgumentList '-Command',"
            . "'Get-Partition -DiskNumber $disk | Where-Object { -not \$_.DriveLetter -and \$_.Size -lt 1GB } | "
            . "Add-PartitionAccessPath -AssignDriveLetter'");
        my $letter = ps("(Get-Partition -DiskNumber $disk | Get-Volume | "
            . "Where-Object { \$_.FileSystemLabel -eq 'bootfs' -and \$_.DriveLetter }).DriveLetter");
        $boot = uc($letter) . ':' if $letter =~ /^[A-Z]$/i;
    }
    die "no bootfs volume with a drive letter on disk $disk\n" if !$boot;
    die "$boot does not look like a Pi boot partition (no config.txt)\n" if !-f "$boot\\config.txt";
    print "boot partition: $boot\n";
    return $boot;
}

#-------------------------------------------------------------------
# 4. cloud-init files
#-------------------------------------------------------------------

my $hash = crypt_password($pipw);
my $passline = $hash
    ? "    passwd: \"$hash\""
    : "    plain_text_passwd: \"$pipw\"";
my $keys = $pubkey
    ? "    ssh_authorized_keys:\n      - $pubkey\n"
    : '';

my $bootstrap = '';
if (!$no_bootstrap)
{
    open my $fh, '<', $SETUP_SH or die "$SETUP_SH: $!\n";
    my @lines = <$fh>;
    close $fh;
    s/\r?\n\z// for @lines;
    my $body = join '', map { "      $_\n" } @lines;
    my $flags = $with_myiot ? ' --with-myiot' : '';
    $bootstrap = <<"EOF";

write_files:
  - path: /usr/local/sbin/rpi_setup.sh
    permissions: "0755"
    owner: root:root
    content: |
$body
runcmd:
  - [ sh, -c, "/usr/local/sbin/rpi_setup.sh$flags > /var/log/rpi_setup.log 2>&1" ]

power_state:
  mode: reboot
  message: rpi_card.pl first boot complete
  condition: true
EOF
}

my $user_data = <<"EOF";
#cloud-config
# written by rpi_card.pl for $host

hostname: $host
manage_etc_hosts: true
timezone: $tz
locale: en_US.UTF-8
keyboard:
  layout: us

users:
  - name: pi
    groups: users,adm,dialout,audio,netdev,video,plugdev,cdrom,games,input,gpio,spi,i2c,render,sudo
    shell: /bin/bash
    lock_passwd: false
$passline
$keys    sudo: ALL=(ALL) NOPASSWD:ALL

enable_ssh: true
ssh_pwauth: true
$bootstrap
EOF

my $aps = '';
for my $w (@wifi)
{
    my ($ssid, $pw) = split /=/, $w, 2;
    die "--wifi needs SSID=PASSWORD: $w\n" if !defined $pw;
    $aps .= "        \"$ssid\":\n          password: \"$pw\"\n";
}
my $network_config = <<"EOF";
# written by rpi_card.pl for $host
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    eth0:
      dhcp4: true
      optional: true
EOF
if ($aps)
{
    $network_config .= <<"EOF";
  wifis:
    wlan0:
      dhcp4: true
      optional: true
      regulatory-domain: "$country"
      access-points:
$aps
EOF
}

write_lf("$boot\\user-data", $user_data);
write_lf("$boot\\network-config", $network_config);
write_lf("$boot\\meta-data", "instance-id: $host\nlocal-hostname: $host\n")
    if !-s "$boot\\meta-data";

print "\ncard for $host is ready in $boot\n";
print "  wifi: ", (join(', ', map { (split /=/)[0] } @wifi) || 'none'), "\n";
print "  bootstrap: ", ($no_bootstrap ? 'no' : "rpi_setup.sh runs on first boot, then reboots"), "\n";
print "eject the card, boot the Pi, then:\n";
print "  /c/Perl/bin/perl.exe rpi_card.pl --check $host", ($sshkey ? " --sshkey $sshkey" : ' --no-sshkey'), "\n";
exit 0;


#-------------------------------------------------------------------
# --check HOST: report the state of a running Pi over ssh
#-------------------------------------------------------------------

sub check_pi
{
    my ($h) = @_;
    my $target = ($h =~ /\./) ? $h : "$h.local";
    # The commands go to the Pi as a script on stdin, so nothing here
    # passes through cmd.exe or the remote shell's quoting.
    my $script = <<"EOF";
echo "== host: \$(hostname)  ip: \$(hostname -I)"
echo "== uptime: \$(uptime -p)"
echo "== cloud-init: \$(cloud-init status 2>/dev/null || echo n/a)"
echo "== setup log:"; tail -n 5 /var/log/rpi_setup.log 2>/dev/null || echo "  (none)"
echo "== mounts:"; mount | grep -E "base_data|SanDisk" || echo "  (none)"
echo "== services:"
for s in artisan fileServer myIOTServer; do printf "  %-12s %s\\n" \$s "\$(systemctl is-active \$s 2>/dev/null)"; done
echo "== audio:"; aplay -l 2>/dev/null | grep "^card" || echo "  (no cards)"
echo "== temp:"; ls /base_data/temp/artisan 2>/dev/null || echo "  (none)"
echo "== http: \$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:$ARTISAN_PORT/ || echo down)"
EOF
    my $tmpdir = 'C:\_temp\base-apps-artisan';
    mkdir $tmpdir if !-d $tmpdir;
    my $tmp = "$tmpdir\\rpi_check.sh";
    open my $fh, '>', $tmp or die "$tmp: $!\n";
    binmode $fh;
    print $fh $script;
    close $fh;
    my $auth = $sshkey ? "-i $sshkey -o BatchMode=yes" : '';
    print "checking $target\n";
    my $text = `ssh $auth -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new pi\@$target bash -s < $tmp 2>&1`;
    print $text;
    return ($? == 0) ? 0 : 1;
}

#-------------------------------------------------------------------
# helpers
#-------------------------------------------------------------------

sub ps
    # run a PowerShell expression, return trimmed stdout
{
    my ($expr) = @_;
    $expr =~ s/"/\\"/g;
    my $out = `powershell -NoProfile -NonInteractive -Command "$expr" 2>&1`;
    $out =~ s/^\s+|\s+$//g;
    return $out;
}


sub crypt_password
    # SHA-512 crypt via openssl if present (git-bash has one); '' if not
{
    my ($pw) = @_;
    my @salt = ('a' .. 'z', 'A' .. 'Z', '0' .. '9');
    my $salt = join '', map { $salt[rand @salt] } 1 .. 12;
    my $h = `openssl passwd -6 -salt $salt "$pw" 2>nul`;
    chomp $h;
    return ($h =~ /^\$6\$/) ? $h : '';
}

sub write_lf
    # write text with LF endings, no BOM (cloud-init is picky)
{
    my ($path, $text) = @_;
    open my $fh, '>', $path or die "$path: $!\n";
    binmode $fh;
    print $fh $text;
    close $fh;
    print "wrote ", basename($path), "\n";
}
