#--------------------------------------
# wTaskBar.pm
#--------------------------------------
# Executed by Windows Scheduler on User log on.
#
# Cannot run this from the User's startup folder as it needs Administrator
# access to start and stop the service:  Otherwise, you could create a shortcut,
#
#	target: C:\Perl\bin\wperl.exe /base/apps/artisan/wTaskBar.pm
#	starting directory:	C:\base\apps\artisan
#   place in: C:\Users\Patrick\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
#
# So, instead we have use the task scheduler and provide credentials:
#
# 	start menu:  taskschd.msc
#	Task Scheduler Library folder, then click on New Folder
#	name: _artisanTaskBar
#   click on folder, create Task
#		Name: _artisanTaskBar
#		Check Radio Button Run only when user is logged on
#		Tried but did not work:
#			check Radio Run whether user is logged on or not
#			check Do not store password.
#		check Run with highest Privileges
#   	Configure for:  Windows 10
#	Triggers: At log on
#		Begin the task: On log on of any user
#   	check Radio Any User
#	Actions: New
#		Start a program
#       Program/Script: C:\Perl\bin\wperl.exe
#		Arguments: /base/apps/artisan/wTaskBar.pm
#		Stsrt In: C:\base\apps\artisan
#   Conditions
#		and uncheck the Stop if the computer switches to battery power
#		then uncheck the Start the task only if the computer is on AC power
#	Settings
#		uncheck Stop taks if runs longer than 3 days
#   Save it, will ask for password.
#
# And to run it from desktop, create a shortcut:
#
#		C:\Windows\System32\schtasks.exe /run /tn "_artisanTaskBar\_artisanTaskBar"
#
# A simple shortcut with wperl.exe /base/apps/artisan/wTaskBar.pm
# fails to get the wifi ipAddress for some reason.



# DESIGN (Ideas)
#
#	Single click brings up a small Player thing with transport, volume, etc,
#   	that goes away when you click else where in the screen.
#   Double click brings up the webUI in a new (stand-alone) browser window
#	Right click shows a context menu containing
#
#			start/stop server
#			mini-player
#				shows the same mini-player but not disappearing
#				and perhaps always on top


package taskBarIcon;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::Service;
	# Fun stuff.  This works!
	#	my $services = {};
	#	Win32::Service::GetServices('',$services);
	#	display_hash(0,0,"Services",$services);
use Wx qw(:everything);
use Wx::Event qw(
	EVT_MENU
	EVT_UPDATE_UI
    EVT_TASKBAR_LEFT_DOWN );
use artisanUtils;
use base qw( Wx::TaskBarIcon );

Pub::Utils::initUtils(1);


my $dbg_icon = 0;

display($dbg_icon,0,"----------------------------------------------");
display($dbg_icon,0,"wTaskBar.pm starting");
display($dbg_icon,0,"----------------------------------------------");
display($dbg_icon,0,"perl_dir=$artisan_perl_dir");
display($dbg_icon,0,"server_ip($server_ip) server_port($server_port)");




my $SERVICE_NAME = '_artisan';

my ($ID_MINI_PLAYER,
	$ID_WEB_UI,
	$ID_START_SERVICE,
	$ID_STOP_SERVICE,
	$ID_CLOSE_ICON ) = (100..199);
my $menu_commands = {
	$ID_MINI_PLAYER 	=> [ 'Mini Player',		'Open modeless Artisan Mini Player Window' ],
	$ID_WEB_UI			=> [ 'Web UI',			'Open the Artisan WebUI in Browser' ],
	$ID_START_SERVICE 	=> [ 'Start Service',	'Start the Artisan Perl Service' ],
	$ID_STOP_SERVICE	=> [ 'Stop Service',	'Stop the Artisan Perl Service' ],
	$ID_CLOSE_ICON		=> [ 'Close',			'Remove the Artisan Icon from the Taskbar' ]};

my $app;
	# fowarded for callt to ExitMainLoop

Wx::InitAllImageHandlers();
my $icon_name = "$artisan_perl_dir/webui/images/artisan_16.png";
my $icon = Wx::Icon->new($icon_name,wxBITMAP_TYPE_PNG );




my ($SERVICE_CHECKPOINT,
	$SERVICE_STOPPED,
	$SERVICE_START_PENDING,
	$SERVICE_STOP_PENDING,
	$SERVICE_RUNNING,
	$SERVICE_CONTINUE_PENDING,
	$SERVICE_PAUSE_PENDING,
	$SERVICE_PAUSED) = (0..7);


sub new
{
    my ($class) = @_;
	display($dbg_icon,0,"taskBarIcon::new() called");
	my $this = $class->SUPER::new();
	display($dbg_icon,0,"taskBarIcon::new() back from SUPER::new()");

	my $ok = $this->IsOk();
	return !error("tackBarIcon::new() !ok") if !$ok;
	$this->SetIcon($icon, "Artisan");

	EVT_TASKBAR_LEFT_DOWN($this,\&onPopupMenu);
	EVT_MENU($this,-1,\&onCommand);
	EVT_UPDATE_UI($this,-1,\&onUpdateUI);

	display($dbg_icon,0,"taskBarIcon::new() returning");
	return $this;
}


sub onUpdateUI
{
	my ($this,$event) = @_;
	my $id = $event->GetId();
	my $service_status = {};
	Win32::Service::GetStatus('',$SERVICE_NAME,$service_status);
	my $state = $service_status->{CurrentState} || 0;
	my $enable = $state == $SERVICE_RUNNING;
	$enable = 1 if $id == $ID_CLOSE_ICON;
	$enable = ($state == ($SERVICE_STOPPED ? 1 : 0))
		if $id == $ID_START_SERVICE;
	$event->Enable($enable);
}


sub onPopupMenu
{
    my ($this) = @_;
	display($dbg_icon,0,"taskBarIcon::onPopupMenu($this) called");
	my $menu = Wx::Menu->new();
	foreach my $id ($ID_MINI_PLAYER..$ID_CLOSE_ICON)
	{
		my $desc = $menu_commands->{$id};
		$menu->Append($id,$desc->[0],$desc->[1],,wxITEM_NORMAL);
		$menu->AppendSeparator() if $id == $ID_WEB_UI || $id == $ID_STOP_SERVICE;
	}
	$this->PopupMenu($menu);
}



sub onCommand
{
	my ($this,$event) = @_;
	my $id = $event->GetId();

	if ($id == $ID_MINI_PLAYER)
	{
		display($dbg_icon,0,"onCommand(MINI_PLAYER)");
	}
	elsif ($id == $ID_WEB_UI)
	{
		display($dbg_icon,0,"onCommand(WEB_UI)");
		startWebUI();
	}
	elsif ($id == $ID_START_SERVICE)
	{
		display($dbg_icon,0,"onCommand(START_SERVICE)");
		Win32::Service::StartService('',$SERVICE_NAME);
	}
	elsif ($id == $ID_STOP_SERVICE)
	{
		display($dbg_icon,0,"onCommand(STOP_SERVICE)");
		Win32::Service::StopService('',$SERVICE_NAME);
	}
	elsif ($id == $ID_CLOSE_ICON)
	{
		$app->ExitMainLoop();
	}


	$event->Skip();
}



sub startWebUI
{
	display($dbg_icon,0,"startWebUI()");
	my $start_dir = "c:\\base\\apps\\artisan";
	my $url = "http://$server_ip:$server_port/webui";
	my $ff_args = "-new-window";

	# Trying to get the ui to popup without a Firefox frame (search and tab bars)

	my $enclosure =
		'data:text/html;charset=utf-8,'.
		'<!DOCTYPE html><html><body><script>window.open("' . $url . '", '.
		'"_blank","height=400,width=600,menubar=no,location=no,toolbar=no,left=100,top=100")'.
		'</script></body></html>';

	my $default_browser = 'C:\Program Files\Mozilla Firefox\firefox.exe';

	my $cmd = $default_browser ?
		"\"$default_browser\" $ff_args $url" :
		"start $url/artisan.html";

	display($dbg_icon,0,"startWebUI($cmd,$start_dir)");

	Pub::Utils::execNoShell($cmd,$start_dir);
}






package taskBarApp;
use strict;
use warnings;
use threads;
use threads::shared;
use Error qw(:try);
use Wx qw(:everything);
use artisanUtils;
use base qw( Wx::App );

my $dbg_app = 0;


sub OnInit
{
	my ($this) = @_;
	display($dbg_app,0,"taskBarApp::OnInit() called");
	my $taskbaricon = taskBarIcon->new();
	error("Could not create taskBarIcon") if !$taskbaricon;
	return $taskbaricon;
}


$app = taskBarApp->new();

if ($app)
{
AFTER_EXCEPTION:

    try
    {
		display($dbg_app,0,"calling taskBarApp::MainLoop()");
        $app->MainLoop();
        display($dbg_app,0,"back from taskBarApp::MainLoop()");
    }

    catch Error with
    {
        my $ex = shift;   # the exception object
        display($dbg_app,0,"exception: $ex");
        error($ex);
        my $msg = "!!! taskBarApp caught an exception !!!\n\n";
        my $dlg = Wx::MessageDialog->new(undef,$msg.$ex,"Exception Dialog",wxOK|wxICON_EXCLAMATION);
        $dlg->ShowModal();
        goto AFTER_EXCEPTION if (1);
    };

    display($dbg_app,0,"finishing taskBarApp()");
}


display($dbg_app,0,"taskBarApp done");


1;
