module dwinbar.widgets.phone_battery;

import dwinbar.backend.dbus;
import dwinbar.widgets.battery;
import dwinbar.widget;
import dwinbar.kdeconnect;
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

class PhoneBatteryWidget : BatteryWidget
{
	this(FontFamily font, KDEConnectDevice device)
	{
		super(font);
		this.device = device;
		unknownIcon = read_image("res/icon/cellphone-erase.png").premultiply;
		batteryFullIcon = read_image("res/icon/battery-charging-full.png").premultiply;
		batteryIcon.loadAll("res/icon/battery-");
		chargingIcon.loadAll("res/icon/battery-charging-");
		if (!batteryIcon.images.length)
			throw new Exception("No battery icons found");
		updateClock.start();
	}

	override void update(Bar bar)
	{
		if (updateClock.peek <= 400.msecs)
			return;
		updateClock.reset();
		if (tick++ >= 25)
		{
			tick = 0;
			updateDBus();
			BatteryState newState = BatteryState.unknown;
			int newBatteryLevel = device.charge;
			if (device.isReachable)
				newState = device.isCharging ? (newBatteryLevel == 100
						? BatteryState.fullyCharged : BatteryState.charging) : BatteryState.discharging;
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
		}
		if (batteryState == BatteryState.charging)
		{
			animatedBatteryLevel += 5;
			if (animatedBatteryLevel > 105)
				animatedBatteryLevel = batteryLevel;
			queueRedraw();
		}
	}

	override IFImage redraw(bool vertical, Bar bar, bool hovered)
	{
		//dfmt off
		enum ulong phone =
			(0b00000000UL << 56) |
			(0b00011110UL << 48) |
			(0b00110011UL << 40) |
			(0b00111111UL << 32) |
			(0b00100001UL << 24) |
			(0b00100001UL << 16) |
			(0b00100001UL << 8) |
			(0b00011110UL)
		;
		//dfmt on

		auto ret = super.redraw(vertical, bar, hovered);
		if (batteryState == BatteryState.unknown)
			return ret;

		assert(ret.c == 4);
		foreach (i; 0 .. 62)
		{
			int x = i & 0b111;
			int y = i >> 3;
			if (x == 7)
				continue;
			ret.pixels[(x + y * ret.w) * 4 .. (x + y * ret.w) * 4 + 4] = (phone & (1UL << i)) != 0UL ? 0xFF
				: 0;
		}
		return ret;
	}

private:
	int tick = 25;
	KDEConnectDevice device;
}
