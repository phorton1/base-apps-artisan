# 2023-12-09 - ffmpeg & fpcalc

There are a few things of interest that are touched on in this document.
The discussion starts with understanding my previous port of ffmpeg and fpcalc
as found in my src-fpcalc repository, and includes some ideas for other
approaches to using ffmpeg.

- the database field FILE_MD5 is a hash of the entire media file,
  including tags, and used to relate media Files to cached 'fpcalc_info' text files.
- my port of chromaprint fpcalc gets the hash of the internal decoded stream,
  STREAM_MD5, that can be used to identify a media Files that contain identical streams,
  regardless of changes to Tags or container type.
- I *thought* that the chromaprint FINGERPRINT_MD5 could somehow be used to identify
  'same recordings' in different files, but it's really useless as-is.
- ffmpeg may be usable for transcoding, i.e. to address the fact that the
  HTML Renderer cannot play WMA files without codec plugins.

The two main loose ideas in my head were to

- use ffmpeg directly from Perl via library bindings
- understand and 'fix' the 'fingerprints' so they 'worked' to identify duplicate recordings.


## Downloads on this date

To wit, the first thing I did was to locate the current ffmpeg source on github,
at https://github.com/FFmpeg/FFmpeg, fork it to my github account, and clone it to
/src/ffmpeg.  I now believe that is a fruitless path to follow and have deleted
the fork and the local clone.

In addition, I went to the Downloads page at https://ffmpeg.org, and from there
procededed to to get pre-built Windows x64 executables and libraries as of this date.
I was initially thinking that I would find Chromaprint as a library (DLL) that could
be called from Perl, but that was not the case.

I downloaded the following files to /zip/apps/ffmpeg

- https://www.gyan.dev/ffmpeg/builds/ffmpeg-git-full.7z
- https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full.7z
- https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.7z
- https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full-shared.7z
- https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl-shared.zip

Only the last release-full-shared.7z contains libraries, and does not seem
to contain Chromaprint (fpcalc), nor can I correlate the contents of what libraries
the website advertises should be in the folder. I now no longer believe that
trying to use the libraries from Perl is the best approach, and now believe
that Chromaprint (fpcalc) is not included in any of those pre-built libraries.

However, the downloads DO contain executables for ffmpeg.exe, ffplay.exe,
and ffprobe.exe which *may* be useful, so I am keeping all of the downloads
in /zip.  I will probably use the ffmpeg.exe from ffmpeg-release-essentials.7z,
if needed, in the future.

As of this checkin, I have not yet delved into using ffmpeg.exe for transcoding.
I don't really like the idea of further complicating my machine and Perl installation
by 'installing' ffmpeg on my machine and using Perl bindings.  In the end I would
probably just use ffmpeg.exe from the artisan/bin directory with temp files.

Still looking for Chromapring/fpcalc, I then went to https://acoustid.org/chromaprint
and downloaded a Windows executable of the latest version of fpcalc.exe

- https://github.com/acoustid/chromaprint/releases/download/v1.5.1/chromaprint-fpcalc-1.5.1-windows-x86_64.zip

This download contains an fpcalc.exe executable on which I did extensive testing
as detailed below and have copied to the artisan/bin/fpcalc_prebuilt_1.5.1.exe.
I added a test program, /docs/tests/fptest.pm, which can be used from that directory.
In the end the results from fpcalc_prebuilt_1.5.1.exe are substantially the
same as those from my old fpcalc_linux_win.0.09.exe


## Usage of My version of fpcalc_linux_win.0.09.exe

As of this checkin, Artisan uses /bin/fpcalc_linux_win.0.09.exe.
I believe it is the same as the fpcalc.exe found in
/src/releases/win32/fpcalc.exe.gz.  The file /bin/fpcalc_orig_win.exe
is vestigial, essentially useless, and will be deleted.

Artisan currently calls fpcalc_linux_win.0.09.exe with the following
parameters:

-md5
-stream_md5
-default length: 120 secs
-default algo: CHROMAPRINT_ALGORITHM_TEST2

To begin with, I identified two recordings which are essentially
identical, but are in different MP3 files:

- test1.mp3 == C:\mp3s\albums\Rock\Main\The Beach Boys - The Greatest Hits Vol 1\03 - Surfer Girl.mp3
- test2.mp3 == C:\mp3s\singles\Rock\Main\The Beach Boys - Capitol Years Disc 1\08 - Surfer Girl.mp3

I here summarize the contents of the database, and existing fpcalc_info files for those
two MP3 files.  The first four lines of each are from the database. The lines starting at
AV_SAMPLE_FMT are from the fpcalc_info cache files, which are called FILE_MD5.txt.
I leave the actual FINGERPRINT out of this md file for length reasons.

*test1.mp3*

- id = 5fbfcfba7db47c5bf4c80d012529fe51
- file_md5 = c3843a377940d752014abe35888ead8a
- duration = 148000
- size = 3553830
- AV_SAMPLE_FMT=s16
- DURATION=148
- STREAM_MD5=5fbfcfba7db47c5bf4c80d012529fe51
- stream_len=13052160
- num_frames=5665
- num_good_frames=5665
- num_consume_failures=0
- num_gotframe_failures=0
- FRAME_MD5=c80ff627224b9e403824d295f71df43a
- FPCALC_MD5=d14cad1421cca5539f61cda18ea8f614
- FINGERPRINT_MD5=b53299c01a8f8b6ee6e820cd7d68533d

*test2.mp3*

- id = bd06548c0eabc0065e9a24b8ccd51a87
- file_md5 = 69abfa5e8f393fde7dca54abd55c7bf1
- duration = 148000
- size = 2372057
- AV_SAMPLE_FMT=s16
- DURATION=148
- STREAM_MD5=bd06548c0eabc0065e9a24b8ccd51a87
- stream_len=13049856
- num_frames=5664
- num_good_frames=5664
- num_consume_failures=0
- num_gotframe_failures=0
- FRAME_MD5=6751a45a0dea25525330f87aa3df2500
- FPCALC_MD5=73bb8a37033b60d28ad539ccaca7be92
- FINGERPRINT_MD5=70c44f6b8022288d8f96965fc5537a94

I then re-ran fpcalc_linux_win.0.09.exe on both files and determined
that they produce the same results

*test1.mp3*

STREAM_MD5=5fbfcfba7db47c5bf4c80d012529fe51
FILE=test1.mp3
DURATION=148
FINGERPRINT_MD5=b53299c01a8f8b6ee6e820cd7d68533d

*test2.mp3*

STREAM_MD5=bd06548c0eabc0065e9a24b8ccd51a87
FILE=test2.mp3
DURATION=148
FINGERPRINT_MD5=70c44f6b8022288d8f96965fc5537a94


## New fpcalc.exe (fpcalc_prebuilt_1.5.1.exe)

Command line Options:
  -format NAME   Set the input format name
  -rate NUM      Set the sample rate of the input audio
  -channels NUM  Set the number of channels in the input audio
  -length SECS   Restrict the duration of the processed input audio (default 120)
  -chunk SECS    Split the input audio into chunks of this duration
  -algorithm NUM Set the algorithm method (default 2)
  -overlap       Overlap the chunks slightly to make sure audio on the edges is fingerprinted
  -ts            Output UNIX timestamps for chunked results, useful when fingerprinting real-time audio stream
  -raw           Output fingerprints in the uncompressed format
  -signed        Change the uncompressed format from unsigned integers to signed (for pg_acoustid compatibility)
  -json          Print the output in JSON format
  -text          Print the output in text format
  -plain         Print the just the fingerprint in text format
  -version       Print version information

Of course it doesn't have options for producing MD5s, and particularly
the STREAM_MD5 and FINGERPRINT_MD5 that I use.  Nonetheless I
tested it extensively.  Running it on the two afore mentioned files
produced the following results.  Here I am including the full FINGERPRINTs
even though they are very long lines of text for an MD file.

**test1.mp3**

DURATION=147
FINGERPRINT=AQADtJeiq8Hz4z-Mt5jzCXeiBueDJKeI8ME7Ck0S4tzx0DjRh3h-HK6C5sihMpzxp3h1HOUv3BnchEb-4CIj4pOO_riDJxeF8zj-I0cybcfhB8ePS_B3_Pi7onHC48ezIycaHtoXI4_i4MYaMDZuuMZ-4v7QB1dwxSrOD92PMD_0CLm249fQvMKB5kfUQ1eRJ0o1fHyCKTtdhE8GXQijW3j4wDkminhChfiD7cbx1CluvLmwV-iOsjvyQ_8QfvCD_jh6-IQe0cXPo7kiEx8eTPMJMdVwHI5-tBczPNoX4g9C_1CUPRNy6qCN6NGFc9AZxCd6NI_xzceZD82zI5x6JP_Ro9yOT7nwozqadUcSZM4yXKkj9HCOp33gSRlC59KhHzlKounY49EF_gz84zQeH1dyMHqCMHJEqB_-XLge6PqGMLtQK8O94Ed_8JSOnjgvXDfys4GWUHnQ50KkHufRX-h1wXgE19lRyWrQfUZzXIxxTRcePUMowScRPgvu5LgWzMoDYmaeoCtzwlFUoXaQH8kVlLvQUMkVvGiq8KjS4zePHzmR3Dl-obkFP1GKViHxk6h0ZinCHK8KHfmPPjhzwV2swWPRLhEuPhv-o1eyYVgqErkUHZp45FGO58R5OMeb48f3TfCz5EhOHfl1XLqK5tHRHw92cD_yZFCu6EO75PB7NPnxbYcqpcmRT-itwUt8lHODnx-eCKdyPBmuo3zwHVeSBemYHYmPPTp-4Q8eShsaTtHBScqBk8a-B0cT_ujD4fmQ_3g0WdCuNMIbhOmGHz0J80LQZmnwCjFFHeUrNEVHX3BMo-9Rv8J23YitJJCeI9xufKiUiKC-NOhz4zSe4glybdDGR0ek3JVxhSdK2Dpq3ejRvMGPX8Qt4hKDUbl1MPIFX0R-iBolIgZ1HT1-lHoQZhGD8VHUDIkv4sc_NBPap8ePdjn8Z2iK5AvyUPgjND_Rj0StfXhPfCm6iceTovkxEc_B7HAR8T5Eh0a69WhfCtfRxGHR7fiE_2j44xKaf3jSGJeNnmjO41YS1ciN59CTV1DEnYRPIbSj4zZ-PELzHLWOxtvRx2BFI86UZ0SvGcqRH99hPsWJ-4N__BLytvAu3CruwCp-Qsez4c1hOUpQKAe9I7LOoGq-CL9w-Ed4nPmh88Ef9JKNXwmhKT3y47hN3ENv-ImOykX-QpcmBSFXo8mF82i5w1_Qbyil5MJ_PI0Cx4d5C_kyTIQUB1skIQ7M5ugT5cEvHM0z9MdPXA_8kQjU9UP47PiP88QZNMfOPPiP7MQVTHmS41QK5w9RZciXazh_9PjxtWjmR_hxRcRlvEL5KsU3HWHGBkk6_DiP9qqKRmGLayWyJ8EpnIicfUEPnzzqLfhx9cPDoAt3-A-qI6dQj9BzI8ePf2vwialx7fjYY5vEDCV-4-KDZ8dHI-EV5FGyXPiHKw9yE3oxPV8I9yi3JMKVRaguQQt6NFxu_BQKLVWOMzz-40efkEJzHD8-IbRXNE-Pn9gtNPmRxccj7PiOHrlRLZKHJ3eQ6_iSZRq0XssQ5tg11GKD7Bl0NlMR_vjy4NRnvDxe4Qp6UBf-4MrmI88HbTkRPgcVM3iIPSPy5tBR7wh_wRHZCJ24HLG9QA_yuUavo3Fj9HmE5seDV0EbLbnhH9cjJM-NSDgXkHfQ_5jCTMGjVbjUBmV3TP0Qp1DOIU84CU9efAyOahks_gipI-lxGc8P1yz-HH03TBnl4z8Y8UXjawgUic2DVKMuPEe1F2d2Cg-OmFsgH_HRi0NzJSmO45KR50HyG_1xsUNP_ISvVMhT6NGRJ2psNOuDHn-EL08x84ilx5BSHWEmPdhzwu_xOriC-KmOLotUaMljfEd-4sJd4sePiiI25Wh-PEtx_EPVKUdTZciP5CL-g3n04dNx12iSMDN2_MgX4he0HzkTOBKF7sN54eER7hBnI8cvY4pDFic_NM7Rh8glIVmeBD2-D39VvM7ww8cbcOKRbw-SPR2ObspxCt_BI1n2E9-W4_1wKPpxbTiPqoerHZ2Pf4JyfcgPpslF-Dn8wy--TER5PMeVJehV-FHhCdW0g1n4oAm3dMh16D_y6OCPH2j443hnnMctSUGV9_iRD88eAtpppDgPZv9xHj_-4w3CJMnlQJMYNkGeBz9KHs3zCPTT4bqG5MsRJjnGHd4lPDn8D_2H58d9NE6uEGk19D3UTLmhri_6J7BD5NTx5UJJHs9x9EKYKscbkoQcOcX_Bl8ifEKpI4xz4Qquw5dwSnh4nMeUpNmRjSqSkflwhcZxXHjj4JmFk1GQJkfSX0EpNYebJCaYH7-KUi_CUIEuBR_iV_AR3cS5HafCB7oW3GioHKGV4R_64QvqfTgqLdkRJ9kPG9qzGHeQL0cflBnydA2eBn5uHL-O52jqjPh2nMpDWMnjozeh87iTUehfwbXR98g7fJM65MX9QB_yB2eOpjbOqKgS5viJnIH2Iq0yPPG04BX-E78OK8qRTAsV5DeaX0GPJ7hSF30-Fc2P87iS4SF-PFmbwxG14sfxqPiL5g1KHvkCNZSOSo2oFGEYMbiU40cfNCeeYx-aJxlRaZEQbtDCIe8EH9cTPNuFS0K4ZhD1HI6PXAE1tKGQKwl0DTkzC7X6wBMAA4CAwBhiEAMGAuMUQkYRRRUiAgghhEHAGQWQIgCSAQVBFDnmkACKEQKAEcAYwbQyBhHFlHBEMASEoEBRgAFQBghACAPGECdIQ8AIQIgDjiBCxAAECUGkQ0wWAARRQgBhCDEGUQeAYgAQ4wCxRBDGhCHWAEGAcCogYgRQGDkEiCECICOEwAwoBhhABjhABBCCAYMIYIIhBIhRgBAnhAGSEQrAIUAAxhQBihgADIHKK0CIAoAIIggwUAlKEFHCMAEAUAAhIgADgAnmkDMCGOCMEgJpAhEAEBGFiAOMCSAUNswIIAkwhBChCECAIEYJAwAQBAwAiChBhCBAOWUAAMggCzwAQhAAkEAMKQGFAkghJgCgBikgEBECAEGAcwYohyASRCCEAQIIEDCAIQYZABgBAgEhgDKJMYUA0IYjA8AAEjigIEXIgYGcMcRQ4RADBAghkDIAMOMQsgoIIhgiBgBAAAGCAAYFoAI54oASQBgAnAFIMASMJAAYIJEBBBAiJBFGSKIQBEAoRgyABBBgAQFWAQIIkQoA4RAAAkAjDAGKGQEEIA4ZhYRwQglDBGIACCSEsMRggoATRhlBhBNMAuAEIQgSQIgDgCgiECLECSEBFUgZhBARRHijiBAQUQCIQIYwQ4wgiggrCAOWFAMoRwwAo4gQRAAFGDOCCFKRNAJ6oowwSgAiCIHGCSIIMUQ5YQwBwCFBDAJKiGSBQRoBhpEEykJChEDGAMEFI0IY5RhggBggDRDCAO0IAopJpIwByinoAQQAACIQUYQBBgRAShjIAEAAGIoEMkAgJwAAzAHrjFCUOAQEgsYzQAAmAADlACNAAQYcMAYAJoSBQikDjEIECCKAAEoYgQBCgjBxFQAAcREEYlJAYgiDxsAEEXIUAIEABACAJIYAABBiCDRMMSeAkEYJQAFwUABJiAACCIUEAkIwARQCigBimAJKKWOJAAAAJoQAihABgGECIUCGoAIhQpgxgDBGLWMIFEEhIIAQZwwTAgA

The new fingerprint is different than mine starting around char 2732

NEW FINGERPRINT=AQADtJeiq8Hz4z-Mt5jzCXeiBueDJKeI8ME7Ck0S4tzx0DjRh3h-HK6C5sihMpzxp3h1HOUv3BnchEb-4CIj4pOO_riDJxeF8zj-I0cybcfhB8ePS_B3_Pi7onHC48ezIycaHtoXI4_i4MYaMDZuuMZ-4v7QB1dwxSrOD92PMD_0CLm249fQvMKB5kfUQ1eRJ0o1fHyCKTtdhE8GXQijW3j4wDkminhChfiD7cbx1CluvLmwV-iOsjvyQ_8QfvCD_jh6-IQe0cXPo7kiEx8eTPMJMdVwHI5-tBczPNoX4g9C_1CUPRNy6qCN6NGFc9AZxCd6NI_xzceZD82zI5x6JP_Ro9yOT7nwozqadUcSZM4yXKkj9HCOp33gSRlC59KhHzlKounY49EF_gz84zQeH1dyMHqCMHJEqB_-XLge6PqGMLtQK8O94Ed_8JSOnjgvXDfys4GWUHnQ50KkHufRX-h1wXgE19lRyWrQfUZzXIxxTRcePUMowScRPgvu5LgWzMoDYmaeoCtzwlFUoXaQH8kVlLvQUMkVvGiq8KjS4zePHzmR3Dl-obkFP1GKViHxk6h0ZinCHK8KHfmPPjhzwV2swWPRLhEuPhv-o1eyYVgqErkUHZp45FGO58R5OMeb48f3TfCz5EhOHfl1XLqK5tHRHw92cD_yZFCu6EO75PB7NPnxbYcqpcmRT-itwUt8lHODnx-eCKdyPBmuo3zwHVeSBemYHYmPPTp-4Q8eShsaTtHBScqBk8a-B0cT_ujD4fmQ_3g0WdCuNMIbhOmGHz0J80LQZmnwCjFFHeUrNEVHX3BMo-9Rv8J23YitJJCeI9xufKiUiKC-NOhz4zSe4glybdDGR0ek3JVxhSdK2Dpq3ejRvMGPX8Qt4hKDUbl1MPIFX0R-iBolIgZ1HT1-lHoQZhGD8VHUDIkv4sc_NBPap8ePdjn8Z2iK5AvyUPgjND_Rj0StfXhPfCm6iceTovkxEc_B7HAR8T5Eh0a69WhfCtfRxGHR7fiE_2j44xKaf3jSGJeNnmjO41YS1ciN59CTV1DEnYRPIbSj4zZ-PELzHLWOxtvRx2BFI86UZ0SvGcqRH99hPsWJ-4N__BLytvAu3CruwCp-Qsez4c1hOUpQKAe9I7LOoGq-CL9w-Ed4nPmh88Ef9JKNXwmhKT3y47hN3ENv-ImOykX-QpcmBSFXo8mF82i5w1_Qbyil5MJ_PI0Cx4d5C_kyTIQUB1skIQ7M5ugT5cEvHM0z9MdPXA_8kQjU9UP47PiP88QZNMfOPPiP7MQVTHmS41QK5w9RZciXazh_9PjxtWjmR_hxRcRlvEL5KsU3HWHGBkk6_DiP9qqKRmGLayWyJ8EpnIicfUEPnzzqLfhx9cPDoAt3-A-qI6dQj9BzI8ePf2vwialx7fjYY5vEDCV-4-KDZ8dHI-EV5FGyXPiHKw9yE3oxPV8I9yi3JMKVRaguQQt6NFxu_BQKLVWOMzz-40efkEJzHD8-IbRXNE-Pn9gtNPmRxccj7PiOHrlRLZKHJ3eQ6_iSZRq0XssQ5tg11GKD7Bl0NlMR_vjy4NRnvDxe4Qp6UBf-4MrmI88HbTkRPgcVM3iIPSPy5tBR7wh_wRHZCJ24HLG9QA_yuUavo3Fj9HmE5seDV0EbLbnhH9cjJM-NSDgXkHfQ_5jCTMGjVbjUBmV3TP0Qp1DOIU84CU9efAyOahks_gipI-lxGc8P1yz-HH03TBnl4z8Y8UXjawgUic2DVKMuPEe1F2d2Cg-OmFsgH_HRi0NzJSmO45KR50HyG_1xsUNP_ISvVMhT6NGRJ2psNOuDHn-EL08x84ilx5BSHWEmPdhzwu_xOriC-KmOLotUaMljfEd-4sJd4sePiiI25Wh-PEtx_EPVKUdTZciP5CL-g3n04dNx12iSMDN2_MgX4he0HzkTOBKF7sN54eER7hBnI8cvY4pDFic_NM7Rh8glIVmeBD2-D39VvM7ww8cbcOKRbw-SPR2ObspxCt_BI1n2E9-W4_1wKPpxbTiPqoerHZ2Pf4JyfcgPpslF-Dn8wy--TER5PMeVJehV-FHhCdW0g1n4oAm3dMh16D_y6OCPH2j443hnnMctSUGV9_iRD88eAtpppDgPZv9xHj_-4w3CJMnlQJMYNkGeBz9KHs3zCPTT4bqG5MsRJjnGHd4lPDn8D_2H58d9NE6uEGk19D3UTLmhri_6J7BD5NTx5UJJHs9x9EKYKscbkoQcOcX_Bl8ifEKpI4xz4Qquw5dwSnh4nMeUpNmRjSqSkflwhcZxXHjj4JmFk1GQJkfSX0EpNYebJCaYH7-KUi_CUIEuBR_iV_AR3cS5HafCB7oW3GioHKGV4R_64QvqfTgqLdkRJ9kPG9qzGHeQL0cflBnydA2eBn5uHL-O52jqjPh2nMpDWMnjozeh87iTUehfwbXR98g7fJM65MX9QB_yB2eOpjbOqKgS5viJnIH2Iq0yPPG04BX-E78OK8qRTAsV5DeaX0GPJ7hSF30-Fc2P87iS4SF-PFmbwxG14sfxqPiL5g1KHvkCNZSOSo2oFGEYMbiU40cfNCeeYx-aJxlRaZEQbtDCIe8EH9cTPNuFS0K4ZhD1HI6PXAE1tKGQKwl0DTkzC7X6wBMAA4CAwBhiEAMGAuMUQkYRRRUiAgghhEHAGQWQIgCSAQVBFDnmkACKEQKAEcAYwbQyBhHFlHBEMASEoEBRgAFQBghACAPGECdIQ8AIQIgDjiBCxAAECUGkQ0wWAARRQgBhCDEGUQeAYgAQ4wCxRBDGhCHWAEGAcCogYgRQGDkEiCECICOEwAwoBhhABjhABBCCAYMIYIIhBIhRgBAnhAGSEQrAIUAAxhQBihgADIHKK0CIAoAIIggwUAlKEFHCMAEAUAAhIgADgAnmkDMCGOCMEgJpAhEAEBGFiAOMCSAUNswIIAkwhBChCECAIEYJAwAQBAwAiChBhCBAOWUAAMggCzwAQhAAkEAMKQGFAkghJgCgBikgEBECAEGAcwYohyASRCCEAQIIEDCAIQYZABgBAgEhgDKJMYUA0IYjA8AAEjigIEXIgYGcMcRQ4RADBAghkDIAMOMQsgoIIhgiBgBAAAGCAAYFoAI54oASQBgAnAFIMASMJAAYIJEBBBAiJBFGSKIQBEAoRgyABBBgAQFWAQIIkQoA4RAAAkAjDAGKGQEEIA4ZhYRwQglDBGIACCSEsMRggoATRhlBhBNMAuAEIQgSQIgDgCgiECLECSEBFUgZhBARRHijiBAQUQCIQIYwQ4wgiggrCAOWFAMoRwwAo4gQRAAFGDOCCFKRNAJ6oowwSgAiCIHGCSIIMUQ5YQwBwCFBDAJKiGSBQRoBhpEEykJChEDGAMEFI0IY5RhggBggDRDCAO0IAopJpIwByinoAQQAACIQUYQBBgRAShjIAEAAGIoEMkAgJwAAzAHrjFCUOAQEgsYzQAAmAADlACNAAQYcMAYAJoSBQikDjEIECCKAAEoYgQBCgjBxFQAAcREEYlJAYgiDxsAEEXIUAIEABACAJIYAABBiCDRMMSeAkEYJQAFwUABJiAACCIUEAkIwARQCigBimAJKKWOJAAAAJoQAihABgGECIUCGoAIhQpgxgDBGLWMIFEEhIIAQZwwTAgA
OLD FINGERPRINT=AQADtJeiq8Hz4z-Mt5jzCXeiBueDJKeI8ME7Ck0S4tzx0DjRh3h-HK6C5sihMpzxp3h1HOUv3BnchEb-4CIj4pOO_riDJxeF8zj-I0cybcfhB8ePS_B3_Pi7onHC48ezIycaHtoXI4_i4MYaMDZuuMZ-4v7QB1dwxSrOD92PMD_0CLm249fQvMKB5kfUQ1eRJ0o1fHyCKTtdhE8GXQijW3j4wDkminhChfiD7cbx1CluvLmwV-iOsjvyQ_8QfvCD_jh6-IQe0cXPo7kiEx8eTPMJMdVwHI5-tBczPNoX4g9C_1CUPRNy6qCN6NGFc9AZxCd6NI_xzceZD82zI5x6JP_Ro9yOT7nwozqadUcSZM4yXKkj9HCOp33gSRlC59KhHzlKounY49EF_gz84zQeH1dyMHqCMHJEqB_-XLge6PqGMLtQK8O94Ed_8JSOnjgvXDfys4GWUHnQ50KkHufRX-h1wXgE19lRyWrQfUZzXIxxTRcePUMowScRPgvu5LgWzMoDYmaeoCtzwlFUoXaQH8kVlLvQUMkVvGiq8KjS4zePHzmR3Dl-obkFP1GKViHxk6h0ZinCHK8KHfmPPjhzwV2swWPRLhEuPhv-o1eyYVgqErkUHZp45FGO58R5OMeb48f3TfCz5EhOHfl1XLqK5tHRHw92cD_yZFCu6EO75PB7NPnxbYcqpcmRT-itwUt8lHODnx-eCKdyPBmuo3zwHVeSBemYHYmPPTp-4Q8eShsaTtHBScqBk8a-B0cT_ujD4fmQ_3g0WdCuNMIbhOmGHz0J80LQZmnwCjFFHeUrNEVHX3BMo-9Rv8J23YitJJCeI9xufKiUiKC-NOhz4zSe4glybdDGR0ek3JVxhSdK2Dpq3ejRvMGPX8Qt4hKDUbl1MPIFX0R-iBolIgZ1HT1-lHoQZhGD8VHUDIkv4sc_NBPap8ePdjn8Z2iK5AvyUPgjND_Rj0StfXhPfCm6iceTovkxEc_B7HAR8T5Eh0a69WhfCtfRxGHR7fiE_2j44xKaf3jSGJeNnmjO41YS1ciN59CTV1DEnYRPIbSj4zZ-PELzHLWOxtvRx2BFI86UZ0SvGcqRH99hPsWJ-4N__BLytvAu3CruwCp-Qsez4c1hOUpQKAe9I7LOoGq-CL9w-Ed4nPmh88Ef9JKNXwmhKT3y47hN3ENv-ImOykX-QpcmBSFXo8mF82i5w1_Qbyil5MJ_PI0Cx4d5C_kyTIQUB1skIQ7M5ugT5cEvHM0z9MdPXA_8kQjU9UP47PiP88QZNMfOPPiP7MQVTHmS41QK5w9RZciXazh_9PjxtWjmR_hxRcRlvEL5KsU3HWHGBkk6_DiP9qqKRmGLayWyJ8EpnIicfUEPnzzqLfhx9cPDoAt3-A-qI6dQj9BzI8ePf2vwialx7fjYY5vEDCV-4-KDZ8dHI-EV5FGyXPiHKw9yE3oxPV8I9yi3JMKVRaguQQt6NFxu_BQKLVWOMzz-40efkEJzHD8-IbRXNE-Pn9gtNPmRxccj7PiOHrlRLZKHJ3eQ6_iSZRq0XssQ5tg11GKD7Bl0NlMR_vjy4NRnvDxe4Qp6UBf-4MrmI88HbTkRPgcVM3iIPSPy5tBR7wh_wRHZCJ24HLG9QA_yuUavo3Fj9HmE5seDV0EbLbnhH9cjJM-NSDgXkHfQ_5jCTMGjVbjUBmV3TP0Qp1DOIU84CU9efAyOahks_gipI-lxGc8P1yz-HH03TBnl4z8Y8UXjawgUic2DVKMuPEe1F2d2Cg-OmFsgH_HRi0NzJSmO45KR50HyG_1xsUNP_ISvVMhT6NGRJ2psNOuDHn-EL08x84ilx5BSHWEmPdhzwu_xOriC-KmOLotUaMljfEd-4sJd4sePiiI25Wh-PEtx_EPVKUdTZciP5CL-g3n04dNx12iSMDN2_MgX4he0HzkTOBKF7sN54eER7hBnI8cvY4pDFic_NM7Rh8glIVmeBD2-D39VvM7ww8cbcOKRbw-SPR2ObspxCt_BI1n2E9-W4_1wKPpxbTiPqoerHZ2Pf4JyfcgPpslF-Dn8wy--TER5PMeVJehV-FHhCdW0g1n4oAm3dMh16D_y6OCPH2j443hnnMctSUGV9_iRD88eAtpppDgPZv9xHj_-4w3CJMnlQJMYNkGeBz9KHs3zCPTT4bqG5MsRJjnGHd4lPDn8D_2H58d9NE6uEGk19D3UTLmhri_6J7BD5NTx5UJJHs9x9EKYKscbkoQcOcX_Bl8ifEKpI4xz4Qquw5dwSnh4nMeUpNmRjSqSkflwhcZxXHjj4JmFk1GQJkfSX0EpNYebJCaYH7-KUi_CUIEuBR_iV_AR3cS5HafCB7oW3GioHKGV4R_6HV-Oeh-OSkt2xEn2w4b2LMYd5MvRB2WGPF2Dp4GfG8ev4zmaOiO-HafyEFby-OhN6DzuZBT6V3Bt9D3yDt-kDnlxP9CH_MGZo6mNMyqqhDl-ImegvUirDE88LXiF_8Svw4pyJNNCBfmN5lfQ4wmu1EWfT0Xz4zyuZHiIH0_W5nBErfhxPCr-onmDkke-QA2lo1IjKkUYRgwu5fjRB82J59iH5klGVFokhBu0cMg7wcf1BM924ZIQrhlEPYfjI1dADW0o5EoCXUPOzEKtPvAEA4CAwBhiEAMGAuMUQkYRRRUiAgghhEHAGQWQIgCSAQVBFDnmkACKEQKAEcAYwbQyBhHFlHBEMASEoEBRgAFQBghACAPGECdIQ8AIQIgDjiBCxAAECUGkQ0wWAARRQgBhCDEGUQeAYgAQ4wCxRBDGhCHWAEGAcCogYgRQGDkEiCECICOEwAwoBhhABjhABBCCAYMIYIIhBIhRgBAnhAGSEQrAIUAAxhQBihgADIHKK0CIAoAIIggwUAlKEFHCMAEAUAAhIgADgAnmkDMCGOCMEgJpAhEAEBGFiAOMCSAUNswIIAkwhBChCECAIEYJAwAQBAwAiChBhCBAOWUAAMggCzwAQhAAkEAMKQGFAkghJgCgBikgEBECAEGAcwYohyASRCCEAQIIEDCAIQYZABgBAgEhgDKJMYUA0IYjA8AAEjigIEXIgYGcMcRQ4RADBAghkDIAMOMQsgoIIhgiBgBAAAGCAAYFoAI54oASQBgAnAFIMASMJAAYIJEBBBAiJBFGSKIQBEAoRgyABBBgAQFWAQIIkQoA4RAAAkAjDAGKGQEEIA4ZhYRwQglDBGIACCSEsMRggoATRhlBhBNMAuAEIQgSQIgDgCgiECLECSEBFUgZhBARRHijiBAQUQCIQIYwQ4wgiggrCAOWFAMoRwwAo4gQRAAFGDOCCFKRNAJ6oowwSgAiCIHGCSIIMUQ5YQwBwCFBDAJKiGSBQRoBhpEEykJChEDGAMEFI0IY5RhggBggDRDCAO0IAopJpIwByinoAQQAACIQUYQBBgRAShjIAEAAGIoEMkAgJwAAzAHrjFCUOAQEgsYzQAAmAADlACNAAQYcMAYAJoSBQikDjEIECCKAAEoYgQBCgjBxFQAAcREEYlJAYgiDxsAEEXIUAIEABACAJIYAABBiCDSMOcWcAEIaJQAFwEEBJCECCCAUEggIwQRQCCgCiGEKKKWMJQIAAJgQAihCBACGCYQAGYIKhAhhxgDCGLWMIVAEhYAAQpwxTAgA

**test2.mp3**

DURATION=147
FINGERPRINT=AQADtJ-U5DJ-NDlKptj3CZcTNfiD6ESyD-8IJyFaHs9xHv1xV8fhJoF_hA_03DhL48ero_wF2RnEikaeBzcjvJN2HPWNa8Z9Cj9u5Do0bUcOHx-u44K_48ffoTlvvCG-Ix_RHlq-GHkUBzfWgDkew8VO436EPriCKz7Ob_gRRofG6Mjl47uGvoIPND-iQ16RM1Gq4eMTTNnpInyCi0gWHc_ywPkxmXgSJsHvwPew4-mL-3hzYa_w493xI_mRz2iOfgZ-NCeSjy7ynGiuyAw-PFh9IllSDTl-eEd7UXh6Fc8jhD4UZU-HnAUdInqUCyd0Bj8R6mge4zP-G_1yIQwP-T_C4zu6SU_woDqa50jiI2cGVqmH-oGDp8zhKjtC7tKhB3lRoqmK58XPgMmP_njc4xIYXSlSOcqg6fiPP4GeI8zWGbUovB5-9AdPHj1xHtdF5GehJVQeos8R_ehrXBeuC8YjuOZRXWHwfPBxFdd0fN8QSoJ_9FGC3MlxLZj1gMf-JOjCLBXhKKpQG3mO5ArKXWi4XMFfNBWDylmN58d_5IfuHHkp9BaeyOjDDD9RvlmQfkevQkd-Fg965oIfw5PaoR1xMXk2_OilDRuoiUT0QY2iB-GV48yJH82Jynhz_JHguEdyJjzy4_xQMnrQPMeHneCOXIXyJB_aJYdfNPmHbzveJoeuT8itofzRLLlxMx5OPMrxJMN1PCiPrwrxKkRC_YiuHI9xC4-1BQ2n6DhzcMRpzNmDowmPPlTwfPiP3Bd0MfHQ90hr9OgL80GONkuDVzhFHSFfuMd5wTFT9KidC74-THqSI9mRZXdwBZUSgTob9MfF403xBLk26B_CqGaESQqP8rB11Dr6oDmeHb_wF5eyCHPugw-ax0bOQ9QoETGo6-iB84Epxoj4TM2gS0TO40MpoeHT40efw3yewTXCLtBDIX-E5kc_UvhRSvmCz-gm5nhSND8m4gfz4xh5H8lDpFs9tD-uG5XDBo12fMLR8PlwCc3xmLjSFD3RHLeiHbldHJfMCBOjEz51hHaE-3iOo3-IpmKOXjkaM8aNbGI-ovMI5cjxw3zQo_9g_fiFvBo8XriKH1ZxQsez49RhPUnQQzlo5PwS7PqCqr2Ewz-KfPmh88H3oJds_EoITTlyHcdt4h56w5eOPkS8F7oqBSF3osmHs8WHhtvRT7iUzEJ_PGkUOD7MBzmHiZBCYUuDfHBW9EmSG38C1M_Q_PiJ6_CXEYH6I_eFPvlxnjjhY-oSHd9jZCeuYMqT45KMxyGaZIi3azjzoweeGx5roVeOJxGJy7hQOje-XUGYUQuSdMJznGjvqLDChui1g09yxBRO5Hmwf2h-1FuGH696PDy6UIH_BBVyiqhH6Dfy4Mdv42pFPNnx_dgmdSjxGxcfPMN5pKoSIvnEC8-O6wnylHih6PkKPyhFRbikJKh4aLnQo-Fy46cA8ceVhfg__OhFo_lx_McjFblX-OnxEzuaHIyPPDp2PMcZhDeqRTqevAlyHRenQSMpcWh4RI-GWiz4zEjOZirCH1-OU2dxFueEDz18gT0u7kf-Fhr_EHlzMImJp9iPvMcLzcrRX0ijd-i0LEVsL4OO3Dxqf_CT4nngn0ePV9lRawl-uNKF5NGNSPhBPg36Hxs51MlUoZS0Bv_Rf8g1aCIVtGIkIdeLN8oY_EcPZ8mPcNGR9LhxHU0TPkafHX-HZpRJTPvB-EWTXkOgSGwepLou7Dqqs5jD3fiHH_kWqDnioxf8SBF6Ccd15IfeIOyPi0XP4Seay0L4hNCjI5calOFlND_-CN-LPRdiPoaUH2GWPNhP-AwuB9fxVEeohFKhJW2M78hPXHiJ__hRUcSmHD76ECf-4Z1yNBURPkdyEX_QTwefHN_RJOkc7Di-DPk1aEeewCGFLh_O46GDcIc4G8F5GXbIYio_9EfjIFciaFcQ5seHbxaexnguNEdvcCKRzwl0p0N41Ap-qvgOHmH2E6qX4zyuQ9GPy3iG90Hz4XvQfVB4ufiDLH9EmFE--McLcxnKU8FfPMmCa2iepPBQLTw65gGTSFs65Dp05JEPVscP9Id5vDN-3IkkdG-OH7mCZw8B7TSMmPiN6j744_nxBk10GckULUsj5FYjHOfRPI_A9OlwXUO-HMl0bIkeeD-eXIH_oT_-D0_R5yFyRRX6HOp3qEnCD6Wf4TTS6_hyoT9-PDjS6njyDmr242L-4F8iPMR_pE2OK8fhRzouEmc-PHswJc5-ZMvUQ_uRL5nx4zh-POzwKIzg5FaQ9B9yOSEaKyIFxj1-FeXTIQyT8LgU6EP8wz-iH-eU4-6hRzluNNQRfrg-9MOJT8_QH-XCI46WH44G7QwuJ3iO0EOZI066RviN5qPQH9eFo2l1fLOEUyeshAuPOxG0E3cyCv0F1xv6Hu8Qb1KHHBcPfccf5D2a6rhQiTmemkMeaD_SKng8LWgvPCbK6nAS5QhFCsnzFH0-ND8u40l6PNfQ_Dl6HlcyPMSPh-3RRJmOPsXxJMUlpujVoPnxBkkZ6XhicUXKKCwu8XiOBz7x48f0JCPRpJGQByIj5J3QoJeT4NkuXEQ4D-ID68c5ZBraI1-SQNeInDxqhVXgCU_CAwAE0QAQCqQCVBlEFDAECSIIAIIJIIQxgAAKFFAIksCQVA45JoBihAgACAAGMK2QQUQxBQSiwgMhHGAIYCUMEABBBowgRAjPABLACAEIMQ5QpghDgBhApEMKkAKEQUIISYhBFChggBFEQCAIIkgwLJQgCghDgACJOQGUM4ggwAghzAjlmIQGMIAUcIAIIAATkDjAhBBKJGCMAYIIJ4gwRipCgUIAGCaQYgQgxIBBQiFlFHAACAAEJUQRwQhiRBhjGACIAAWQcIYcQQwwSgiAgGECAoWgQIiABwgwQikwAJHMECsUEQgIIQQgSkgAAHGCAgCEcAQRQQhSwCljkDbUAguAEIIAogEiSAkkAASIA0CNQAAYIQQAEgHHDFBOGSGAMIIggwECAgxDDAkGOIKAcgIgtogwCgoCnwGeAAccoAgkQIpgyAFiBBBGOMSEEEIgYgCwRiFkFRBCMGCIE4AgAJRiQAAqiHBACSAEIwAYgARTghFghERUECEkAQIopAEQShFgCCFEMAMApQIYoohQQAiHAEAAGiIMAYohBQBhyCgmBBYCCkMEUAgIJIQQRBRjiEHACeOsAIIhpggATijnCCDEAUC4QIg4AYABQgCkEFBIEUEEaEAgRQQACgDDCUEGECMIEYI4YAghQhBiAAVJCEUAIAIoAJhAQDBGhUHSAOGJYMYCAYggBBknCECEGGSIA0IhAihSkCCghKgIAIO0FRhJAASFhApFDBCCPSGsZIwwAhQSwgiBTKLKIcAIEcADCAAwgjiiCAMKIGEEckABBJhBBFEgkBOOCesMU4BYBIQBwjNAhDQCGCaAEoITYwBgghgJhFAAGOWIEAQYowCAgjADEBLKABCWAgAAApgQhRCDAASMEUCUAEQgYTiCSCFHABAAAkEIR4ACYQQAAgmCCGGGISKUA0A4pyBAgjAm5CDAGCoQYIIRioASBghjLAJSEMQoYAAIAAwhiAFggBAIATIIUSQRBQwBgBgmQWPKKQOEIYAgSAAwQggDAQ

The old fingerprint and new fingerprint appear to be same.

NEW FINGERPRINT=AQADtJ-U5DJ-NDlKptj3CZcTNfiD6ESyD-8IJyFaHs9xHv1xV8fhJoF_hA_03DhL48ero_wF2RnEikaeBzcjvJN2HPWNa8Z9Cj9u5Do0bUcOHx-u44K_48ffoTlvvCG-Ix_RHlq-GHkUBzfWgDkew8VO436EPriCKz7Ob_gRRofG6Mjl47uGvoIPND-iQ16RM1Gq4eMTTNnpInyCi0gWHc_ywPkxmXgSJsHvwPew4-mL-3hzYa_w493xI_mRz2iOfgZ-NCeSjy7ynGiuyAw-PFh9IllSDTl-eEd7UXh6Fc8jhD4UZU-HnAUdInqUCyd0Bj8R6mge4zP-G_1yIQwP-T_C4zu6SU_woDqa50jiI2cGVqmH-oGDp8zhKjtC7tKhB3lRoqmK58XPgMmP_njc4xIYXSlSOcqg6fiPP4GeI8zWGbUovB5-9AdPHj1xHtdF5GehJVQeos8R_ehrXBeuC8YjuOZRXWHwfPBxFdd0fN8QSoJ_9FGC3MlxLZj1gMf-JOjCLBXhKKpQG3mO5ArKXWi4XMFfNBWDylmN58d_5IfuHHkp9BaeyOjDDD9RvlmQfkevQkd-Fg965oIfw5PaoR1xMXk2_OilDRuoiUT0QY2iB-GV48yJH82Jynhz_JHguEdyJjzy4_xQMnrQPMeHneCOXIXyJB_aJYdfNPmHbzveJoeuT8itofzRLLlxMx5OPMrxJMN1PCiPrwrxKkRC_YiuHI9xC4-1BQ2n6DhzcMRpzNmDowmPPlTwfPiP3Bd0MfHQ90hr9OgL80GONkuDVzhFHSFfuMd5wTFT9KidC74-THqSI9mRZXdwBZUSgTob9MfF403xBLk26B_CqGaESQqP8rB11Dr6oDmeHb_wF5eyCHPugw-ax0bOQ9QoETGo6-iB84Epxoj4TM2gS0TO40MpoeHT40efw3yewTXCLtBDIX-E5kc_UvhRSvmCz-gm5nhSND8m4gfz4xh5H8lDpFs9tD-uG5XDBo12fMLR8PlwCc3xmLjSFD3RHLeiHbldHJfMCBOjEz51hHaE-3iOo3-IpmKOXjkaM8aNbGI-ovMI5cjxw3zQo_9g_fiFvBo8XriKH1ZxQsez49RhPUnQQzlo5PwS7PqCqr2Ewz-KfPmh88H3oJds_EoITTlyHcdt4h56w5eOPkS8F7oqBSF3osmHs8WHhtvRT7iUzEJ_PGkUOD7MBzmHiZBCYUuDfHBW9EmSG38C1M_Q_PiJ6_CXEYH6I_eFPvlxnjjhY-oSHd9jZCeuYMqT45KMxyGaZIi3azjzoweeGx5roVeOJxGJy7hQOje-XUGYUQuSdMJznGjvqLDChui1g09yxBRO5Hmwf2h-1FuGH696PDy6UIH_BBVyiqhH6Dfy4Mdv42pFPNnx_dgmdSjxGxcfPMN5pKoSIvnEC8-O6wnylHih6PkKPyhFRbikJKh4aLnQo-Fy46cA8ceVhfg__OhFo_lx_McjFblX-OnxEzuaHIyPPDp2PMcZhDeqRTqevAlyHRenQSMpcWh4RI-GWiz4zEjOZirCH1-OU2dxFueEDz18gT0u7kf-Fhr_EHlzMImJp9iPvMcLzcrRX0ijd-i0LEVsL4OO3Dxqf_CT4nngn0ePV9lRawl-uNKF5NGNSPhBPg36Hxs51MlUoZS0Bv_Rf8g1aCIVtGIkIdeLN8oY_EcPZ8mPcNGR9LhxHU0TPkafHX-HZpRJTPvB-EWTXkOgSGwepLou7Dqqs5jD3fiHH_kWqDnioxf8SBF6Ccd15IfeIOyPi0XP4Seay0L4hNCjI5calOFlND_-CN-LPRdiPoaUH2GWPNhP-AwuB9fxVEeohFKhJW2M78hPXHiJ__hRUcSmHD76ECf-4Z1yNBURPkdyEX_QTwefHN_RJOkc7Di-DPk1aEeewCGFLh_O46GDcIc4G8F5GXbIYio_9EfjIFciaFcQ5seHbxaexnguNEdvcCKRzwl0p0N41Ap-qvgOHmH2E6qX4zyuQ9GPy3iG90Hz4XvQfVB4ufiDLH9EmFE--McLcxnKU8FfPMmCa2iepPBQLTw65gGTSFs65Dp05JEPVscP9Id5vDN-3IkkdG-OH7mCZw8B7TSMmPiN6j744_nxBk10GckULUsj5FYjHOfRPI_A9OlwXUO-HMl0bIkeeD-eXIH_oT_-D0_R5yFyRRX6HOp3qEnCD6Wf4TTS6_hyoT9-PDjS6njyDmr242L-4F8iPMR_pE2OK8fhRzouEmc-PHswJc5-ZMvUQ_uRL5nx4zh-POzwKIzg5FaQ9B9yOSEaKyIFxj1-FeXTIQyT8LgU6EP8wz-iH-eU4-6hRzluNNQRfrg-9MOJT8_QH-XCI46WH44G7QwuJ3iO0EOZI066RviN5qPQH9eFo2l1fLOEUyeshAuPOxG0E3cyCv0F1xv6Hu8Qb1KHHBcPfccf5D2a6rhQiTmemkMeaD_SKng8LWgvPCbK6nAS5QhFCsnzFH0-ND8u40l6PNfQ_Dl6HlcyPMSPh-3RRJmOPsXxJMUlpujVoPnxBkkZ6XhicUXKKCwu8XiOBz7x48f0JCPRpJGQByIj5J3QoJeT4NkuXEQ4D-ID68c5ZBraI1-SQNeInDxqhVXgCU_CAwAE0QAQCqQCVBlEFDAECSIIAIIJIIQxgAAKFFAIksCQVA45JoBihAgACAAGMK2QQUQxBQSiwgMhHGAIYCUMEABBBowgRAjPABLACAEIMQ5QpghDgBhApEMKkAKEQUIISYhBFChggBFEQCAIIkgwLJQgCghDgACJOQGUM4ggwAghzAjlmIQGMIAUcIAIIAATkDjAhBBKJGCMAYIIJ4gwRipCgUIAGCaQYgQgxIBBQiFlFHAACAAEJUQRwQhiRBhjGACIAAWQcIYcQQwwSgiAgGECAoWgQIiABwgwQikwAJHMECsUEQgIIQQgSkgAAHGCAgCEcAQRQQhSwCljkDbUAguAEIIAogEiSAkkAASIA0CNQAAYIQQAEgHHDFBOGSGAMIIggwECAgxDDAkGOIKAcgIgtogwCgoCnwGeAAccoAgkQIpgyAFiBBBGOMSEEEIgYgCwRiFkFRBCMGCIE4AgAJRiQAAqiHBACSAEIwAYgARTghFghERUECEkAQIopAEQShFgCCFEMAMApQIYoohQQAiHAEAAGiIMAYohBQBhyCgmBBYCCkMEUAgIJIQQRBRjiEHACeOsAIIhpggATijnCCDEAUC4QIg4AYABQgCkEFBIEUEEaEAgRQQACgDDCUEGECMIEYI4YAghQhBiAAVJCEUAIAIoAJhAQDBGhUHSAOGJYMYCAYggBBknCECEGGSIA0IhAihSkCCghKgIAIO0FRhJAASFhApFDBCCPSGsZIwwAhQSwgiBTKLKIcAIEcADCAAwgjiiCAMKIGEEckABBJhBBFEgkBOOCesMU4BYBIQBwjNAhDQCGCaAEoITYwBgghgJhFAAGOWIEAQYowCAgjADEBLKABCWAgAAApgQhRCDAASMEUCUAEQgYTiCSCFHABAAAkEIR4ACYQQAAgmCCGGGISKUA0A4pyBAgjAm5CDAGCoQYIIRioASBghjLAJSEMQoYAAIAAwhiAFggBAIATIIUSQRBQwBgBgmQWPKKQOEIYAgSAAwQggDAQ
OLD FINGERPRINT=AQADtJ-U5DJ-NDlKptj3CZcTNfiD6ESyD-8IJyFaHs9xHv1xV8fhJoF_hA_03DhL48ero_wF2RnEikaeBzcjvJN2HPWNa8Z9Cj9u5Do0bUcOHx-u44K_48ffoTlvvCG-Ix_RHlq-GHkUBzfWgDkew8VO436EPriCKz7Ob_gRRofG6Mjl47uGvoIPND-iQ16RM1Gq4eMTTNnpInyCi0gWHc_ywPkxmXgSJsHvwPew4-mL-3hzYa_w493xI_mRz2iOfgZ-NCeSjy7ynGiuyAw-PFh9IllSDTl-eEd7UXh6Fc8jhD4UZU-HnAUdInqUCyd0Bj8R6mge4zP-G_1yIQwP-T_C4zu6SU_woDqa50jiI2cGVqmH-oGDp8zhKjtC7tKhB3lRoqmK58XPgMmP_njc4xIYXSlSOcqg6fiPP4GeI8zWGbUovB5-9AdPHj1xHtdF5GehJVQeos8R_ehrXBeuC8YjuOZRXWHwfPBxFdd0fN8QSoJ_9FGC3MlxLZj1gMf-JOjCLBXhKKpQG3mO5ArKXWi4XMFfNBWDylmN58d_5IfuHHkp9BaeyOjDDD9RvlmQfkevQkd-Fg965oIfw5PaoR1xMXk2_OilDRuoiUT0QY2iB-GV48yJH82Jynhz_JHguEdyJjzy4_xQMnrQPMeHneCOXIXyJB_aJYdfNPmHbzveJoeuT8itofzRLLlxMx5OPMrxJMN1PCiPrwrxKkRC_YiuHI9xC4-1BQ2n6DhzcMRpzNmDowmPPlTwfPiP3Bd0MfHQ90hr9OgL80GONkuDVzhFHSFfuMd5wTFT9KidC74-THqSI9mRZXdwBZUSgTob9MfF403xBLk26B_CqGaESQqP8rB11Dr6oDmeHb_wF5eyCHPugw-ax0bOQ9QoETGo6-iB84Epxoj4TM2gS0TO40MpoeHT40efw3yewTXCLtBDIX-E5kc_UvhRSvmCz-gm5nhSND8m4gfz4xh5H8lDpFs9tD-uG5XDBo12fMLR8PlwCc3xmLjSFD3RHLeiHbldHJfMCBOjEz51hHaE-3iOo3-IpmKOXjkaM8aNbGI-ovMI5cjxw3zQo_9g_fiFvBo8XriKH1ZxQsez49RhPUnQQzlo5PwS7PqCqr2Ewz-KfPmh88H3oJds_EoITTlyHcdt4h56w5eOPkS8F7oqBSF3osmHs8WHhtvRT7iUzEJ_PGkUOD7MBzmHiZBCYUuDfHBW9EmSG38C1M_Q_PiJ6_CXEYH6I_eFPvlxnjjhY-oSHd9jZCeuYMqT45KMxyGaZIi3azjzoweeGx5roVeOJxGJy7hQOje-XUGYUQuSdMJznGjvqLDChui1g09yxBRO5Hmwf2h-1FuGH696PDy6UIH_BBVyiqhH6Dfy4Mdv42pFPNnx_dgmdSjxGxcfPMN5pKoSIvnEC8-O6wnylHih6PkKPyhFRbikJKh4aLnQo-Fy46cA8ceVhfg__OhFo_lx_McjFblX-OnxEzuaHIyPPDp2PMcZhDeqRTqevAlyHRenQSMpcWh4RI-GWiz4zEjOZirCH1-OU2dxFueEDz18gT0u7kf-Fhr_EHlzMImJp9iPvMcLzcrRX0ijd-i0LEVsL4OO3Dxqf_CT4nngn0ePV9lRawl-uNKF5NGNSPhBPg36Hxs51MlUoZS0Bv_Rf8g1aCIVtGIkIdeLN8oY_EcPZ8mPcNGR9LhxHU0TPkafHX-HZpRJTPvB-EWTXkOgSGwepLou7Dqqs5jD3fiHH_kWqDnioxf8SBF6Ccd15IfeIOyPi0XP4Seay0L4hNCjI5calOFlND_-CN-LPRdiPoaUH2GWPNhP-AwuB9fxVEeohFKhJW2M78hPXHiJ__hRUcSmHD76ECf-4Z1yNBURPkdyEX_QTwefHN_RJOkc7Di-DPk1aEeewCGFLh_O46GDcIc4G8F5GXbIYio_9EfjIFciaFcQ5seHbxaexnguNEdvcCKRzwl0p0N41Ap-qvgOHmH2E6qX4zyuQ9GPy3iG90Hz4XvQfVB4ufiDLH9EmFE--McLcxnKU8FfPMmCa2iepPBQLTw65gGTSFs65Dp05JEPVscP9Id5vDN-3IkkdG-OH7mCZw8B7TSMmPiN6j744_nxBk10GckULUsj5FYjHOfRPI_A9OlwXUO-HMl0bIkeeD-eXIH_oT_-D0_R5yFyRRX6HOp3qEnCD6Wf4TTS6_hyoT9-PDjS6njyDmr242L-4F8iPMR_pE2OK8fhRzouEmc-PHswJc5-ZMvUQ_uRL5nx4zh-POzwKIzg5FaQ9B9yOSEaKyIFxj1-FeXTIQyT8LgU6EP8wz-iH-eU4-6hRzluNNQRfrg-9MOJT8_QH-XCI46WH44G7QwuJ3iO0EOZI066RviN5qPQH9eFo2l1fLOEUyeshAuPOxG0E3cyCv0F1xv6Hu8Qb1KHHBcPfccf5D2a6rhQiTmemkMeaD_SKng8LWgvPCbK6nAS5QhFCsnzFH0-ND8u40l6PNfQ_Dl6HlcyPMSPh-3RRJmOPsXxJMUlpujVoPnxBkkZ6XhicUXKKCwu8XiOBz7x48f0JCPRpJGQByIj5J3QoJeT4NkuXEQ4D-ID68c5ZBraI1-SQNeInDxqhVXgCU_CAwAE0QAQCqQCVBlEFDAECSIIAIIJIIQxgAAKFFAIksCQVA45JoBihAgACAAGMK2QQUQxBQSiwgMhHGAIYCUMEABBBowgRAjPABLACAEIMQ5QpghDgBhApEMKkAKEQUIISYhBFChggBFEQCAIIkgwLJQgCghDgACJOQGUM4ggwAghzAjlmIQGMIAUcIAIIAATkDjAhBBKJGCMAYIIJ4gwRipCgUIAGCaQYgQgxIBBQiFlFHAACAAEJUQRwQhiRBhjGACIAAWQcIYcQQwwSgiAgGECAoWgQIiABwgwQikwAJHMECsUEQgIIQQgSkgAAHGCAgCEcAQRQQhSwCljkDbUAguAEIIAogEiSAkkAASIA0CNQAAYIQQAEgHHDFBOGSGAMIIggwECAgxDDAkGOIKAcgIgtogwCgoCnwGeAAccoAgkQIpgyAFiBBBGOMSEEEIgYgCwRiFkFRBCMGCIE4AgAJRiQAAqiHBACSAEIwAYgARTghFghERUECEkAQIopAEQShFgCCFEMAMApQIYoohQQAiHAEAAGiIMAYohBQBhyCgmBBYCCkMEUAgIJIQQRBRjiEHACeOsAIIhpggATijnCCDEAUC4QIg4AYABQgCkEFBIEUEEaEAgRQQACgDDCUEGECMIEYI4YAghQhBiAAVJCEUAIAIoAJhAQDBGhUHSAOGJYMYCAYggBBknCECEGGSIA0IhAihSkCCghKgIAIO0FRhJAASFhApFDBCCPSGsZIwwAhQSwgiBTKLKIcAIEcADCAAwgjiiCAMKIGEEckABBJhBBFEgkBOOCesMU4BYBIQBwjNAhDQCGCaAEoITYwBgghgJhFAAGOWIEAQYowCAgjADEBLKABCWAgAAApgQhRCDAASMEUCUAEQgYTiCSCFHABAAAkEIR4ACYQQAAgmCCGGGISKUA0A4pyBAgjAm5CDAGCoQYIIRioASBghjLAJSEMQoYAAIAAwhiAFggBAIATIIUSQRBQwBgBgmQWPKKQOEIYAgSAAwQggDAQ


## Observations

The 'fingerprint' returned by fpcalc.exe IS NOT A FINGERPRINT AT ALL!!
It is merely a set of fourier transforms, 8 per second, over the stream samples.

- the ascii encoded FINGERPRINT is merely the -raw INTS converted to ASCII
- the INTS are time-based and not independent of the starting point.
- new fpcalc.exe gives a different duration


## AcousticId (website and approach)

Further research indicates that the idea was never that the fingerprint
was what I thought it was. According to the author the only way to compare
two files is to compare the RAW INTEGERS, bitwise, with a sliding window,
to develop a BEST SCORE of the number of bit matches across ALL THE BITS.
I tested this in fptest.pm, and have decided NOT TO EVEN TRY.

However, before that, I went through the hassle of (re) creating
a MusicBrainz login (in my passwords file) so that I could try
to submit "fingerprints" to AcousicId.com and see if I got hits
or matches.  I went so far as to get an  acousticId.com 'user key'

- my acousticId.com 'user key'  b'nyct8GAb

This was a total waste of time.  I tried to create a GET request
according to their instructions, using my 'user key', but in fact
I would need to 'register my application' and get an 'application
key' to make such calls.  They offer a short term 'application
key' in their examples, so I made a request using that and it
returned an empty result, i.e. my version of "Surfer Girl"
is not in their database, and to use it I would have to build
THEIR database first.

For completeness, here are the GET requests.

HERES THEIR EXAMPLE: https://api.acoustid.org/v2/lookup?client=k8wx_PUvoAg&duration=641&fingerprint=AQABz0qUkZK4oOfhL-CPc4e5C_wW2H2QH9uDL4cvoT8UNQ-eHtsE8cceeFJx-LiiHT-aPzhxoc-Opj_eI5d2hOFyMJRzfDk-QSsu7fBxqZDMHcfxPfDIoPWxv9C1o3yg44d_3Df2GJaUQeeR-cb2HfaPNsdxHj2PJnpwPMN3aPcEMzd-_MeB_Ej4D_CLP8ghHjkJv_jh_UDuQ8xnILwunPg6hF2R8HgzvLhxHVYP_ziJX0eKPnIE1UePMByDJyg7wz_6yELsB8n4oDmDa0Gv40hf6D3CE3_wH6HFaxCPUD9-hNeF5MfWEP3SCGym4-SxnXiGs0mRjEXD6fgl4LmKWrSChzzC33ge9PB3otyJMk-IVC6R8MTNwD9qKQ_CC8kPv4THzEGZS8GPI3x0iGVUxC1hRSizC5VzoamYDi-uR7iKPhGSI82PkiWeB_eHijvsaIWfBCWH5AjjCfVxZ1TQ3CvCTclGnEMfHbnZFA8pjD6KXwd__Cn-Y8e_I9cq6CR-4S9KLXqQcsxxoWh3eMxiHI6TIzyPv0M43YHz4yte-Cv-4D16Hv9F9C9SPUdyGtZRHV-OHEeeGD--BKcjVLOK_NCDXMfx44dzHEiOZ0Z44Rf6DH5R3uiPj4d_PKolJNyRJzyu4_CTD2WOvzjKH9GPb4cUP1Av9EuQd8fGCFee4JlRHi18xQh96NLxkCgfWFKOH6WGeoe4I3za4c5hTscTPEZTES1x8kE-9MQPjT8a8gh5fPgQZtqCFj9MDvp6fDx6NCd07bjx7MLR9AhtnFnQ70GjOcV0opmm4zpY3SOa7HiwdTtyHa6NC4e-HN-OfC5-OP_gLe2QDxfUCz_0w9l65HiPAz9-IaGOUA7-4MZ5CWFOlIfe4yUa6AiZGxf6w0fFxsjTOdC6Itbh4mGD63iPH9-RFy909XAMj7mC5_BvlDyO6kGTZKJxHUd4NDwuZUffw_5RMsde5CWkJAgXnDReNEaP6DTOQ65yaD88HoeX8fge-DSeHo9Qa8cTHc80I-_RoHxx_UHeBxrJw62Q34Kd7MEfpCcu6BLeB1ePw6OO4sOF_sHhmB504WWDZiEu8sKPpkcfCT9xfej0o0lr4T5yNJeOvjmu40w-TDmqHXmYgfFhFy_M7tD1o0cO_B2ms2j-ACEEQgQgAIwzTgAGmBIKIImNQAABwgQATAlhDGCCEIGIIM4BaBgwQBogEBIOESEIA8ARI5xAhxEFmAGAMCKAURKQQpQzRAAkCCBQEAKkQYIYIQQxCixCDADCABMAE0gpJIgyxhEDiCKCCIGAEIgJIQByAhFgGACCACMRQEyBAoxQiHiCBCFOECQFAIgAABR2QAgFjCDMA0AUMIoAIMChQghChASGEGeYEAIAIhgBSErnJPPEGWYAMgw05AhiiGHiBBBGGSCQcQgwRYJwhDDhgCSCSSEIQYwILoyAjAIigBFEUQK8gAYAQ5BCAAjkjCCAEEMZAUQAZQCjCCkpCgFMCCiIcVIAZZgilAQAiSHQECOcQAQIc4QClAHAjDDGkAGAMUoBgyhihgEChFCAAWEIEYwIJYwViAAlHCBIGEIEAEIQAoBwwgwiEBAEEEOoEwBY4wRwxAhBgAcKAESIQAwwIowRFhoBhAE
HERES test1.mp3: https://api.acoustid.org/v2/lookup?client=k8wx_PUvoAg&duration=147&fingerprint=AQADtJeiq8Hz4z-Mt5jzCXeiBueDJKeI8ME7Ck0S4tzx0DjRh3h-HK6C5sihMpzxp3h1HOUv3BnchEb-4CIj4pOO_riDJxeF8zj-I0cybcfhB8ePS_B3_Pi7onHC48ezIycaHtoXI4_i4MYaMDZuuMZ-4v7QB1dwxSrOD92PMD_0CLm249fQvMKB5kfUQ1eRJ0o1fHyCKTtdhE8GXQijW3j4wDkminhChfiD7cbx1CluvLmwV-iOsjvyQ_8QfvCD_jh6-IQe0cXPo7kiEx8eTPMJMdVwHI5-tBczPNoX4g9C_1CUPRNy6qCN6NGFc9AZxCd6NI_xzceZD82zI5x6JP_Ro9yOT7nwozqadUcSZM4yXKkj9HCOp33gSRlC59KhHzlKounY49EF_gz84zQeH1dyMHqCMHJEqB_-XLge6PqGMLtQK8O94Ed_8JSOnjgvXDfys4GWUHnQ50KkHufRX-h1wXgE19lRyWrQfUZzXIxxTRcePUMowScRPgvu5LgWzMoDYmaeoCtzwlFUoXaQH8kVlLvQUMkVvGiq8KjS4zePHzmR3Dl-obkFP1GKViHxk6h0ZinCHK8KHfmPPjhzwV2swWPRLhEuPhv-o1eyYVgqErkUHZp45FGO58R5OMeb48f3TfCz5EhOHfl1XLqK5tHRHw92cD_yZFCu6EO75PB7NPnxbYcqpcmRT-itwUt8lHODnx-eCKdyPBmuo3zwHVeSBemYHYmPPTp-4Q8eShsaTtHBScqBk8a-B0cT_ujD4fmQ_3g0WdCuNMIbhOmGHz0J80LQZmnwCjFFHeUrNEVHX3BMo-9Rv8J23YitJJCeI9xufKiUiKC-NOhz4zSe4glybdDGR0ek3JVxhSdK2Dpq3ejRvMGPX8Qt4hKDUbl1MPIFX0R-iBolIgZ1HT1-lHoQZhGD8VHUDIkv4sc_NBPap8ePdjn8Z2iK5AvyUPgjND_Rj0StfXhPfCm6iceTovkxEc_B7HAR8T5Eh0a69WhfCtfRxGHR7fiE_2j44xKaf3jSGJeNnmjO41YS1ciN59CTV1DEnYRPIbSj4zZ-PELzHLWOxtvRx2BFI86UZ0SvGcqRH99hPsWJ-4N__BLytvAu3CruwCp-Qsez4c1hOUpQKAe9I7LOoGq-CL9w-Ed4nPmh88Ef9JKNXwmhKT3y47hN3ENv-ImOykX-QpcmBSFXo8mF82i5w1_Qbyil5MJ_PI0Cx4d5C_kyTIQUB1skIQ7M5ugT5cEvHM0z9MdPXA_8kQjU9UP47PiP88QZNMfOPPiP7MQVTHmS41QK5w9RZciXazh_9PjxtWjmR_hxRcRlvEL5KsU3HWHGBkk6_DiP9qqKRmGLayWyJ8EpnIicfUEPnzzqLfhx9cPDoAt3-A-qI6dQj9BzI8ePf2vwialx7fjYY5vEDCV-4-KDZ8dHI-EV5FGyXPiHKw9yE3oxPV8I9yi3JMKVRaguQQt6NFxu_BQKLVWOMzz-40efkEJzHD8-IbRXNE-Pn9gtNPmRxccj7PiOHrlRLZKHJ3eQ6_iSZRq0XssQ5tg11GKD7Bl0NlMR_vjy4NRnvDxe4Qp6UBf-4MrmI88HbTkRPgcVM3iIPSPy5tBR7wh_wRHZCJ24HLG9QA_yuUavo3Fj9HmE5seDV0EbLbnhH9cjJM-NSDgXkHfQ_5jCTMGjVbjUBmV3TP0Qp1DOIU84CU9efAyOahks_gipI-lxGc8P1yz-HH03TBnl4z8Y8UXjawgUic2DVKMuPEe1F2d2Cg-OmFsgH_HRi0NzJSmO45KR50HyG_1xsUNP_ISvVMhT6NGRJ2psNOuDHn-EL08x84ilx5BSHWEmPdhzwu_xOriC-KmOLotUaMljfEd-4sJd4sePiiI25Wh-PEtx_EPVKUdTZciP5CL-g3n04dNx12iSMDN2_MgX4he0HzkTOBKF7sN54eER7hBnI8cvY4pDFic_NM7Rh8glIVmeBD2-D39VvM7ww8cbcOKRbw-SPR2ObspxCt_BI1n2E9-W4_1wKPpxbTiPqoerHZ2Pf4JyfcgPpslF-Dn8wy--TER5PMeVJehV-FHhCdW0g1n4oAm3dMh16D_y6OCPH2j443hnnMctSUGV9_iRD88eAtpppDgPZv9xHj_-4w3CJMnlQJMYNkGeBz9KHs3zCPTT4bqG5MsRJjnGHd4lPDn8D_2H58d9NE6uEGk19D3UTLmhri_6J7BD5NTx5UJJHs9x9EKYKscbkoQcOcX_Bl8ifEKpI4xz4Qquw5dwSnh4nMeUpNmRjSqSkflwhcZxXHjj4JmFk1GQJkfSX0EpNYebJCaYH7-KUi_CUIEuBR_iV_AR3cS5HafCB7oW3GioHKGV4R_64QvqfTgqLdkRJ9kPG9qzGHeQL0cflBnydA2eBn5uHL-O52jqjPh2nMpDWMnjozeh87iTUehfwbXR98g7fJM65MX9QB_yB2eOpjbOqKgS5viJnIH2Iq0yPPG04BX-E78OK8qRTAsV5DeaX0GPJ7hSF30-Fc2P87iS4SF-PFmbwxG14sfxqPiL5g1KHvkCNZSOSo2oFGEYMbiU40cfNCeeYx-aJxlRaZEQbtDCIe8EH9cTPNuFS0K4ZhD1HI6PXAE1tKGQKwl0DTkzC7X6wBMAA4CAwBhiEAMGAuMUQkYRRRUiAgghhEHAGQWQIgCSAQVBFDnmkACKEQKAEcAYwbQyBhHFlHBEMASEoEBRgAFQBghACAPGECdIQ8AIQIgDjiBCxAAECUGkQ0wWAARRQgBhCDEGUQeAYgAQ4wCxRBDGhCHWAEGAcCogYgRQGDkEiCECICOEwAwoBhhABjhABBCCAYMIYIIhBIhRgBAnhAGSEQrAIUAAxhQBihgADIHKK0CIAoAIIggwUAlKEFHCMAEAUAAhIgADgAnmkDMCGOCMEgJpAhEAEBGFiAOMCSAUNswIIAkwhBChCECAIEYJAwAQBAwAiChBhCBAOWUAAMggCzwAQhAAkEAMKQGFAkghJgCgBikgEBECAEGAcwYohyASRCCEAQIIEDCAIQYZABgBAgEhgDKJMYUA0IYjA8AAEjigIEXIgYGcMcRQ4RADBAghkDIAMOMQsgoIIhgiBgBAAAGCAAYFoAI54oASQBgAnAFIMASMJAAYIJEBBBAiJBFGSKIQBEAoRgyABBBgAQFWAQIIkQoA4RAAAkAjDAGKGQEEIA4ZhYRwQglDBGIACCSEsMRggoATRhlBhBNMAuAEIQgSQIgDgCgiECLECSEBFUgZhBARRHijiBAQUQCIQIYwQ4wgiggrCAOWFAMoRwwAo4gQRAAFGDOCCFKRNAJ6oowwSgAiCIHGCSIIMUQ5YQwBwCFBDAJKiGSBQRoBhpEEykJChEDGAMEFI0IY5RhggBggDRDCAO0IAopJpIwByinoAQQAACIQUYQBBgRAShjIAEAAGIoEMkAgJwAAzAHrjFCUOAQEgsYzQAAmAADlACNAAQYcMAYAJoSBQikDjEIECCKAAEoYgQBCgjBxFQAAcREEYlJAYgiDxsAEEXIUAIEABACAJIYAABBiCDRMMSeAkEYJQAFwUABJiAACCIUEAkIwARQCigBimAJKKWOJAAAAJoQAihABgGECIUCGoAIhQpgxgDBGLWMIFEEhIIAQZwwTAgA

Nothing returned.


## Other (cloud based) approaches

Frustrated, I looked for other existing solutions.  I found one which 'worked',
but, of course, I don't want to include (or need) web access in my Server.
However, at the url:

https://www.aha-music.com/identify-songs-music-recognition-online/upload/69abfa5e8f393fde7dca54abd55c7bf1#upload-div

I was able to upload the actual MP3 files and it was able to identify them,
not only as the same song, but was able to tell me WHAT song it was:

test1.mp3 	3553830 	c3843a377940d752014abe35888ead8a
Title: Surfer Girl (1999 Digital Remaster)
Artist: The?Beach?Boys
External IDs: {"isrc":"USCA29900664","iswc":"T-070.244.087-6","upc":"00724352186051"}

test2.mp3 	2372057 	69abfa5e8f393fde7dca54abd55c7bf1
Title: Surfer Girl (1999 Digital Remaster)
Artist: The?Beach?Boys
External IDs: {"isrc":"USCA29900664","iswc":"T-070.244.087-6","upc":"00724352186051"}


## SUMMARY (so far)

Apart from the potential use of ffmpeg.exe for transcoding or converting my WMA
files to MP3s, the work on fpcalc was essentially fruitless.  However, once again,
all of the results are available in artisan/bin and artisan/docs/tests.

Please see /artisan/docs/tests/fptest.pm for more details


---- end of ffmpeg.md ----