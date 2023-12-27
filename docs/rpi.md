# rPi - Artisan Perl Experiments on Raspberry Pi's

Minor bug that under some circumstance Queue playing does not scrollTo
the initial track (switching?  adding?).


See /zip/_rPi/_setup/rPi_Setup.docx for OS & installation details.

## Observations (rPi Browser to Artisan Perl on Windows machine)

- Had real problems with 64bit OS on 4B(1).
- Works well in 3B(0) with old 32bit OS
- Works well on 4B(2A) with 64bit OS

Somewhat better with 4B1 on 32bits

- seems to spend a LOT of time hitting the SDCard
- audio interrupted by browser stuff
- might be a RAM limitation (swapping) particular to 4B vs 3B

Had problems with existing (git_repos) PAT (personal access token)
Creating and using a new (rPi) specific PAT fixed it.

## Decision

The rpi 4B(0) 1GB is a bit slow for practical use.
I will leave it configured, as far as fileServer, with the SD
in it, but will do future Artisan experiments only on the 2GB 4B(2A)

## Ideas

- Replace Boat Car Stereo with combined myIOT/Artisan Server Touch Screen
- Home Stereo / Artisan Server running on rPi with denormalized
  copy of MP3s (USB SSD, HD, or dongle)

Sound options on rPi from Perl are limited. Probable solution is to use
HTML Renderer on rPis for easier access to audio device, then possibly
the existing rPi output, HDMI sound output, or a soundcard (Hat/USB)
