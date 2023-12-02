# SSDP and Win10 Networking

I had a lot of trouble getting SSDP working reliably.

In fact, as of this writing it's still not 100%, but I needed to write
down some of the things I've learned so far.

The implementation/testing of the SSDP is/was intimately related to
issues with Win10 networking.

I thought I had implemented SSDP 'pretty well' when I endeavored
to 'clean it up' and test it and try to fix a few minor bugs,
most notably that my M-SEARCH calls never seemed to work correctly.

In order to figure out what was going on, I started by normalizing
the Perl source code from LENOVO3/github to LENOVO2, so that I could
run dual servers and test their SSDP interactions. That in itself
was a time consuming task, especially as I decided to make sure that
LENOVO2 had all current Win10 updates, and so ended up spending 8+
hours doing updates on the LENOVO2 machine.


## Modified the Artisan UUID and device Friendly Name

I modified $this_uuid presented in artisanUtils,pm to include the
Win10 COMPUTERNAME where it previously ended with 8 hex digits.
Likewise, I modified the 'device xml' in HTTPServer.pm to change
the Friendly Name to Artisan(COMPUTERNAME).


## Wireshark

I soon determined that I needed to see the SSDP packets on each machine
outside of Artisan itself in order to understand what was going on.
So I insstalled WireShark on both machines and learned how to use it
sufficiently to capture UDP packets and filter them by various
criteria for display.


## Switched from THX50 to THX59

Side note:  THX50 (Archer C20 router) seems to be a pain in the ass.
I am switching to THX59 which is one hope closer to the Starlink
router for faster speeds and hopefully better reliability.


## Win10 Home Networking (important)

I have always had difficulty with Win10 home networking between
LENOVO2 and LENOVO3, which I used for the CNC20mm workflow.

LENOVO2 could 'see' LENOVO3 reliably, but not vice-versa.

Likewise, I could send an 'alive' packet from LENOVO2 and
LENOVO3 would reliably see it, but not vice-versa.  My SSDP
packets did not seem to be 'getting out' from LENOVO3 to
LENOVO2.

It turns out that this problem relates to SSDP visibility as well.

After MANY hours of thinking it was the Win10 Defender Firewall,
or other Win10 configuration issues, upto and including creating
specific firewall rules (_prh SSDP) and even at one point completely
disabling the Firewall, all to no avail.

I finally discovered that some
needed services on LENOVO3 were not running.  They were set to
'manual' but were not getting invoked.

I found this page

https://answers.microsoft.com/en-us/windows/forum/all/network-discovery-not-working-windows-10/ac43f9cf-c639-4471-bc00-c6c90dcafef6

which explicitly lists some services that need to be turned on
(made 'Automatic' startup) for Home Networking to work reliably,
once I did that the situation with SSDP started to improve.


- Function Discovery Provider Host (FDPHost)
- Function Discovery Resource Publication (FDResPub)
- Network Connections (NetMan)
- UPnP Device Host (UPnPHost)
- Peer Name Resolution Protocol (PNRPSvc)
- Peer Networking Grouping (P2PSvc)
- Peer Networking Identity Manager (P2PIMSvc)

*I currently have some generous options set for 'All Networks'
on both machines that may not be needed and should be revisited.*


## M-SEARCH ssdp:all bug

*All bugs have been mine!**

Once the 'alive' packets were going in both directions, I
turned to the issue of why my M-SEARCH packets were not
getting from Artisan on LENOVO3 to LENOVO2.

I used Wireshark to look at M-SEARCH packets sent by other
programs and got them to LENOVO2 by changing the search
criteria from ssdp:all to upnp:rootdevice.

Later I realized that I wasnt't answering M-SEARCHES from
ssdp:all, just like I found that I was over-filtering
other messages at other times.  So the problem is solved.


Turns out I was


## SSDP Sockets

I currently use IO::Socket::Multicast for LISTEN and
my own versions of _mcast_send() etc for SEARCH, creating
two different threads with two different sets of SEND/LISTEN
sockets with slightly differnent technologoies.

I feel that there should only need to be one pair, and
that the project shouild be do-able with the unmodified Perl
IO::Socket::Multicast in a single loop (thread).


## my M-SEARCH finds WMP on OTHER machine, but not this one

This is where I started. the 127.0.0.1 versus $server_ip issue.
On LENOVO3

- If I use $server_ip, 0.0.0.0, or don't specify an IP address in
  my M-SEARCH socket, I get results from LENOVO2 WMP, including
  my own server, but nothing from LENOVO3 WMP
- If I use 127.0.0.1 I get LENOVO3 WMP but nothing at all
  from LENOVO2.


Try regular IO::Socket::Multicast

- I currently respond to my own M-SEARCH messages in Listen because
  SEARCH and LISTEN have two different ports and I check $port.


## TODO

- 'Solve' the multiple technologies/threads issue
- Incorporate SSDPTest back into Artisan
- remove custom Win10 Defender Firewall rules
- retore stricter Win10 'All Networks' configuration







------------------------
end of ssdp.pm
