module dwinbar.widgets.battery;

import dwinbar.backend.dbus;
import dwinbar.widget;
import dwinbar.bar;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime.stopwatch;
import std.exception;
import std.file;
import std.math;
import std.path;
import std.range;
import std.stdio;
import std.typecons;
import std.uni;

import tinyevent;

class BatteryWidget : Widget
{
	this()
	{
	}

	this(FontFamily font)
	{
		this.font = font;
	}

	this(FontFamily font, ObjectPath batteryDevice)
	{
		this.font = font;
		loadIcons();
		setDevice(batteryDevice);
		updateClock.start();
	}

	void loadIcons()
	{
		batteryFullIcon = read_image("res/icon/battery-charging-full.png").premultiply;
		batteryIcon.loadAll("res/icon/battery-");
		chargingIcon.loadAll("res/icon/battery-charging-");
		if (!batteryIcon.images.length)
			throw new Exception("No battery icons found");
		unknownIcon = batteryIcon.imageFor(0);
	}

	void setDevice(ObjectPath device)
	{
		systemBus.attach();
		batteryInterface = new PathIface(systemBus.conn, busName("org.freedesktop.UPower"),
				device, interfaceName("org.freedesktop.DBus.Properties"));
	}

	override void loadBase(WidgetConfig config)
	{
		this.font = config.bar.fontFamily;
		updateClock.start();
	}

	override bool setProperty(string property, Json value)
	{
		switch (property)
		{
		case "batteryDevice":
		case "device":
			setDevice(ObjectPath(value.to!string));
			return true;
		default:
			return false;
		}
	}

	override int width(bool) const
	{
		return 18 + cast(int) ceil(measureText(cast() font, 1, batteryLevel.to!string)[0]);
	}

	override int height(bool) const
	{
		return 16;
	}

	override bool hasHover() @property
	{
		return false;
	}

	override IFImage redraw(bool vertical, Bar bar, bool hovered)
	{
		IFImage canvas;
		canvas.w = width(vertical);
		canvas.h = height(vertical);
		canvas.c = ColFmt.RGBA;
		canvas.pixels.length = canvas.w * canvas.h * canvas.c;

		IFImage icon;
		switch (batteryState)
		{
		case BatteryState.charging:
			icon = chargingIcon.imageFor(animatedBatteryLevel);
			break;
		case BatteryState.fullyCharged:
			icon = batteryFullIcon;
			break;
		case BatteryState.empty:
			icon = batteryIcon.imageFor(0);
			break;
		case BatteryState.unknown:
			icon = unknownIcon;
			break;
		default:
			icon = batteryIcon.imageFor(batteryLevel);
			break;
		}
		canvas.draw(icon, 0, 0);
		canvas.drawText(font, 1, batteryLevel.to!string, 17, 14,
				cast(ubyte[4])[0xFF, 0xFF, 0xFF, 0xFF]);
		return canvas;
	}

	override void update(Bar bar)
	{
		if (updateClock.peek <= 400.msecs)
			return;
		updateClock.reset();
		updateDBus();
		double energy = batteryInterface.Get("org.freedesktop.UPower.Device", "Percentage").to!double;
		int newBatteryLevel = cast(int) round(energy);
		auto newState = cast(BatteryState) batteryInterface.Get("org.freedesktop.UPower.Device",
				"State").to!uint;
		if (newBatteryLevel != batteryLevel)
		{
			batteryLevel = newBatteryLevel;
			queueRedraw();
		}
		if (newState != batteryState)
		{
			batteryState = newState;
			animatedBatteryLevel = batteryLevel;
			queueRedraw();
		}
		if (batteryState == BatteryState.charging)
		{
			animatedBatteryLevel += 5;
			if (animatedBatteryLevel > 105)
				animatedBatteryLevel = batteryLevel;
			queueRedraw();
		}
	}

protected:
	FontFamily font;
	PathIface batteryInterface;
	BatteryState batteryState;
	int batteryLevel;
	int animatedBatteryLevel;
	IFImage batteryFullIcon, unknownIcon;
	ImageRange batteryIcon, chargingIcon;
	StopWatch updateClock;
}

enum BatteryState : uint
{
	unknown,
	charging,
	discharging,
	empty,
	fullyCharged,
	pendingCharge,
	pendingDischarge
}
