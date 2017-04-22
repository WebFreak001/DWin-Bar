module dwinbar.widgets.volume;

import dwinbar.backend.xbackend;
import dwinbar.backend.applaunch;
import dwinbar.widget;
import dwinbar.bar;

import x11.Xlib;
import x11.X;

import std.datetime;
import std.format;
import std.conv;
import std.regex;
import std.process;
import std.math;

static import std.stdio;

enum volumeFinder = ctRegex!`\[(\d+)%\] \[(on|off)\]`;
float getVolume()
{
	auto result = execute(["amixer", "sget", "Master"]);
	if (result.status != 0)
		return -2;
	auto match = result.output.matchFirst(volumeFinder);
	if (!match)
		return -2;
	float ret = match[1].to!int / 100.0f;
	if (match[2] == "off")
		return -ret;
	return ret;
}

void setVolume(float volume)
{
	execute(["amixer", "set", "Master", (cast(int)(volume * 100)).to!string ~ "%"]);
}

class VolumeWidget : Widget, IMouseWatch
{
	this()
	{
		_volume = getVolume();

		icons ~= read_png("res/icon/volume-low.png").premultiply;
		icons ~= read_png("res/icon/volume-medium.png").premultiply;
		icons ~= read_png("res/icon/volume-high.png").premultiply;
		icons ~= read_png("res/icon/volume-off.png").premultiply;
	}

	override int width(bool vertical) const
	{
		return icons[0].w + 108;
	}

	override int height(bool vertical) const
	{
		return icons[0].h;
	}

	override bool hasHover() @property
	{
		return true;
	}

	override void mouseDown(bool vertical, int mx, int my, int button)
	{
		if (button == 1)
		{
			down = true;
			mouseMove(vertical, mx, my);
		}
	}

	override void mouseUp(bool vertical, int mx, int my, int button)
	{
		if (button == 1)
		{
			down = false;
			frame = 0;
		}
	}

	override void mouseMove(bool vertical, int mx, int my)
	{
		if (down)
		{
			_volume = (mx - icons[0].w - 8) / 100.0f;
			if (_volume < 0)
				_volume = 0;
			if (_volume > 1)
				_volume = 1;
			queueChange = true;
			changeTimer.reset();
			changeTimer.start();
			updateVolume();
			queueRedraw();
		}
	}

	override void update(Bar bar)
	{
		if (down)
		{
			if (queueChange && changeTimer.peek.to!("msecs", int) >= 50)
			{
				queueChange = false;
				changeTimer.stop();
				setVolume(_volume);
			}
		}
		else
		{
			if (++frame >= 50)
			{
				auto oldVol = _volume;
				_volume = getVolume();
				if (abs(oldVol - _volume) > 0.01f)
					queueRedraw();
				updateVolume();
				frame = 0;
			}
		}
	}

	void updateVolume()
	{
		auto oldIcon = _activeIcon;
		if (_volume < 0)
			_activeIcon = 3;
		else if (_volume <= 0.3f)
			_activeIcon = 0;
		else if (_volume <= 0.6f)
			_activeIcon = 1;
		else if (_volume <= 1)
			_activeIcon = 2;
		if (oldIcon != _activeIcon)
			queueRedraw();
	}

	override IFImage redraw(bool vertical, Bar bar, bool hovered)
	{
		IFImage ret;
		ret.w = width(vertical);
		ret.h = height(vertical);
		ret.c = ColFmt.RGBA;
		ret.pixels.length = ret.w * ret.h * ret.c;
		ret.pixels[] = 0;

		ret.draw(icons[_activeIcon], 0, 0);
		ret.fillRect!4(icons[_activeIcon].w + 8, icons[_activeIcon].h / 2 - 1, 100, 1,
				[0xFF, 0xFF, 0xFF, 0xFF]);
		ret.fillRect!4(icons[_activeIcon].w + 8 + cast(int)(_volume * 100), 0, 2,
				icons[_activeIcon].h, [0xFF, 0xFF, 0xFF, 0xFF]);

		return ret;
	}

private:
	int _activeIcon = 0;
	int frame = 50;
	float _volume;
	IFImage[] icons;
	bool down, queueChange;
	StopWatch changeTimer;
}
