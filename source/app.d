import dwinbar.widgets.battery;
import dwinbar.widgets.phone_battery;
import dwinbar.widgets.clock;
import dwinbar.widgets.mediaplayer;
import dwinbar.widgets.notifications;
import dwinbar.widgets.volume;
import dwinbar.widgets.workspace;

import dwinbar.kdeconnect;

/*import dwinbar.widgets.volume;
import dwinbar.widgets.tray;
import dwinbar.widgets.workspace;*/

import dwinbar.bar;

void main(string[] args)
{
	BarConfiguration config;
	config.fontPrimary = "Roboto:Medium";
	config.fontSecondary = "Roboto:Light";

	PanelConfiguration panelConfig;
	panelConfig.height = 32;

	Bar bar = loadBar(config);

	string left = args.length > 1 ? args[1] : null;
	string right = args.length > 2 ? args[2] : null;

	auto phones = KDEConnectDevice.listDevices();

	//dfmt off
	auto panel1 = bar.addPanel(Screen.First, Dock.Bottom, panelConfig)
		.add(new ClockWidget())
		// find using `dbus-send --print-reply --system --dest=org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower.EnumerateDevices`
		//.add(new BatteryWidget(bar.fontFamily, "/org/freedesktop/UPower/devices/battery_BAT1"))
		//.add(new NotificationsWidget(&bar))
		.add(new VolumeWidget())
		.add(new MprisMediaPlayerWidget(bar.fontFamily, "org.mpris.MediaPlayer2.spotify"))
		//.add(new WorkspaceWidget(bar.x, "DisplayPort-1"))
	;
	if (phones.length)
		panel1.add(new PhoneBatteryWidget(bar.fontFamily, phones[0]));

	if (left.length)
		panel1.add(new WorkspaceWidget(bar.x, left));

	if (right.length)
		bar.addPanel(Screen.Second, Dock.Bottom, panelConfig)
			.add(new ClockWidget())
			.add(new WorkspaceWidget(bar.x, right))
			//.add(new WorkspaceWidget(bar.x, "DisplayPort-0"))
		;
	//dfmt on

	//bar.tray = panel1;
	bar.start();
}
