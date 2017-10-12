import dwinbar.widgets.battery;
import dwinbar.widgets.clock;
import dwinbar.widgets.notifications;
import dwinbar.widgets.volume;
import dwinbar.widgets.workspace;

/*import dwinbar.widgets.volume;
import dwinbar.widgets.tray;
import dwinbar.widgets.workspace;*/

import dwinbar.bar;

void main(string[] args)
{
	BarConfiguration config;
	//config.fontPrimary = "Roboto Medium";
	//config.fontSecondary = "Roboto Light";

	PanelConfiguration panelConfig;
	panelConfig.height = 32;

	Bar bar = loadBar(config);

	//dfmt off
	bar.addPanel(Screen.First, Dock.Bottom, panelConfig)
		.add(new ClockWidget())
		// find using `dbus-send --print-reply --system --dest=org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower.EnumerateDevices`
		.add(new BatteryWidget(bar.fontFamily, "/org/freedesktop/UPower/devices/battery_BAT1"))
		.add(new NotificationsWidget(&bar))
		.add(new VolumeWidget())
		.add(new WorkspaceWidget(bar.x, "HDMI-1"))
	;
	//dfmt on

	//bar.tray = panel1;
	bar.start();
}
