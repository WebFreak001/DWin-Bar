import dwinbar.widgets.battery;
import dwinbar.widgets.phone_battery;
import dwinbar.widgets.clock;
import dwinbar.widgets.mediaplayer;
import dwinbar.widgets.notifications;
import dwinbar.widgets.volume;
import dwinbar.widgets.workspace;

import dwinbar.widget;

import dwinbar.kdeconnect;
import dwinbar.webserver;

/*import dwinbar.widgets.volume;
import dwinbar.widgets.tray;
import dwinbar.widgets.workspace;*/

import dwinbar.bar;

import std.conv;
import std.string;
import std.meta;

import vibe.core.file;
import vibe.core.log;
import vibe.data.json;

bool applyBarConfig(string setting, Json value, ref BarConfiguration config)
{
	switch (setting)
	{
		static foreach (member; AliasSeq!("fontPrimary", "fontSecondary",
				"fontNeutral", "fontFallback"))
		{
	case member:
			__traits(getMember, config, member) = value.to!string;
			return true;
		}
	case "displayName":
		config.displayName = cast(char*) value.to!string.dup.toStringz;
		return true;
	case "spotify":
		clientId = value["clientId"].to!string;
		clientSecret = value["clientSecret"].to!string;
		redirectURL = value["redirectURL"].to!string;
		return true;
	default:
		return false;
	}
}

bool applyPanelConfig(string setting, Json value, ref PanelConfiguration config,
		ref Screen screen, ref Dock dock)
{
	switch (setting)
	{
		static foreach (member; AliasSeq!("height", "barBaselinePadding", "appIconPadding",
				"appBaselineMargin", "widgetBaselineMargin", "focusStripeHeight", "offsetX", "offsetY"))
		{
	case member:
			__traits(getMember, config, member) = value.to!int;
			return true;
		}
	case "enableAppList":
		config.enableAppList = value.to!bool;
		return true;
	case "screen":
		screen = value.to!string
			.to!Screen;
		return true;
	case "dock":
		dock = value.to!string
			.to!Dock;
		return true;
	default:
		return false;
	}
}

void main(string[] args)
{
	Json[string] userConfig = parseJsonString(readFileUTF8("config.json"), "config.json").get!(
			Json[string]);

	BarConfiguration config;
	config.fontPrimary = "Roboto:Medium";
	config.fontSecondary = "Roboto:Light";

	PanelConfiguration panelConfig;
	panelConfig.height = 32;

	Json[] panels;

	foreach (k, v; userConfig)
	{
		if (k == "panels")
		{
			panels = v.get!(Json[]);
			continue;
		}

		if (applyBarConfig(k, v, config))
			continue;

		Screen screen;
		Dock dock;
		if (applyPanelConfig(k, v, panelConfig, screen, dock))
			continue;

		logInfo("Unknown json setting: %s: %s", k, v);
	}

	Bar bar = loadBar(config);
	startSpotifyWebServer();
	scope (exit)
	{
		import std.concurrency : send;

		send(webServerThread, DoExit());
	}

	foreach (panel; panels)
	{
		bar.loadPanel(panel.get!(Json[string]), panelConfig);
	}

	//bar.tray = panel1;
	bar.start();
}

void loadPanel(ref Bar bar, Json[string] settings, PanelConfiguration panelConfig)
{
	Screen screen = Screen.First;
	Dock dock = Dock.Bottom;

	Json[] widgets;
	foreach (k, v; settings)
	{
		if (k == "widgets")
		{
			widgets = v.get!(Json[]);
			continue;
		}

		if (applyPanelConfig(k, v, panelConfig, screen, dock))
			continue;

		logInfo("Unknown panel setting: %s: %s", k, v);
	}

	auto panel = bar.addPanel(screen, dock, panelConfig);

	foreach (widget; widgets)
	{
		panel.addWidget(widget, bar, panelConfig);
	}

	// 	.add(new ClockWidget())
	// 	// find using `dbus-send --print-reply --system --dest=org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower.EnumerateDevices`
	// 	//.add(new BatteryWidget(bar.fontFamily, ObjectPath("/org/freedesktop/UPower/devices/battery_BAT1")))
	// 	//.add(new NotificationsWidget(&bar))
	// 	.add(new VolumeWidget())
	// 	.add(new MprisMediaPlayerWidget(bar.fontFamily, "org.mpris.MediaPlayer2.spotify"))
	// 	//.add(new WorkspaceWidget(bar.x, "DisplayPort-1"))
	// ;
	// if (phones.length)
	// 	panel1.add(new PhoneBatteryWidget(bar.fontFamily, phones[0]));

	// if (left.length)
	// 	panel1.add(new WorkspaceWidget(bar.x, left));

	// if (right.length)
	// 	bar.addPanel(Screen.Second, Dock.Bottom, panelConfig)
	// 		.add(new ClockWidget())
	// 		.add(new WorkspaceWidget(bar.x, right))
	// 		//.add(new WorkspaceWidget(bar.x, "DisplayPort-0"))
	// 	;
	// //dfmt on
}

void addWidget(Panel panel, Json widget, ref Bar bar, PanelConfiguration panelConfig)
{
	string className = widget.type == Json.Type.string ? widget.to!string : widget["type"].to!string;

	auto ret = cast(Widget) Object.factory(className);
	if (!ret)
	{
		logError("Could not find widget %s", className);
		return;
	}
	ret.loadBase(WidgetConfig(&bar, panelConfig));

	if (widget.type == Json.Type.object)
	{
		foreach (k, v; widget.get!(Json[string]))
		{
			if (k == "type")
				continue;
			if (ret.setProperty(k, v))
				continue;

			logInfo("Unknown %s widget config: %s %s", className, k, v);
		}
	}

	panel.add(ret);
}
