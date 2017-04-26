module dwinbar.widgets.clock;

import dwinbar.widget;
import dwinbar.bar;

import std.datetime;
import std.format;
import std.conv;

class ClockWidget : Widget
{
	this(bool showSeconds = true)
	{
		this.showSeconds = showSeconds;
		clockIcon = read_image("res/icon/clock.png").premultiply;
	}

	override int width(bool) const
	{
		if (showSeconds)
			return 70 + 16;
		else
			return 50 + 16;
	}

	override int height(bool) const
	{
		return 16;
	}

	override bool hasHover() @property
	{
		return true;
	}

	override IFImage redraw(bool vertical, Bar bar, bool hovered)
	{
		IFImage ret;
		ret.w = width(vertical);
		ret.h = height(vertical);
		ret.c = ColFmt.RGBA;
		ret.pixels.length = ret.w * ret.h * ret.c;
		ret.pixels[] = 0;

		string clockMajor = format("%02d:%02d", clockTime.hour, clockTime.minute);
		string clockMinor = format("%02d", clockTime.second);

		auto pos = ret.drawText(bar.facePrimary, clockMajor, 0, 14,
				cast(ubyte[4])[0xFF, 0xFF, 0xFF, 0xFF]);
		if (showSeconds)
			ret.drawText(bar.faceSecondary, clockMinor, pos[0] + 2, 14,
					cast(ubyte[4])[0xFF, 0xFF, 0xFF, 0xFF]);

		ret.draw(clockIcon, ret.w - 16, 0);

		return ret;
	}

	override void update(Bar)
	{
		clockTime = Clock.currTime;
		if (lastSecond != clockTime.second)
		{
			queueRedraw();
			lastSecond = clockTime.second;
		}
	}

private:
	IFImage clockIcon;
	SysTime clockTime;
	ubyte lastSecond;
	bool showSeconds;
}
