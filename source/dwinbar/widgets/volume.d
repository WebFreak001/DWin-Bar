module dwinbar.widgets.volume;

import dwinbar.backend.xbackend;
import dwinbar.backend.applaunch;
import dwinbar.widget;
import dwinbar.bar;

import x11.Xlib;
import x11.X;

import std.conv;
import std.datetime;
import std.format;
import std.math;
import std.process;
import std.regex;
import std.string;

static import std.stdio;

float getVolume()
{
	auto result = execute(["pamixer", "--get-volume"]);
	if (result.status != 0)
		return -2;
	float ret = result.output.strip.to!int / 100.0f;
	if (execute(["pamixer", "--get-mute"]).output.strip == "true")
		return -ret;
	else
		return ret;
}

void setVolume(float volume)
{
	execute(["pamixer", "--unmute", "--set-volume", (cast(int)(volume * 100)).to!string]);
}

void setMute()
{
	execute(["pamixer", "--mute"]);
}

void setUnmute()
{
	execute(["pamixer", "--unmute"]);
}

void toggleMute()
{
	if (execute(["pamixer", "--get-mute"]).output.strip == "true")
		setUnmute();
	else
		setMute();
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
		return icons[0].w + 102 + 8;
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
			if (mx < icons[$ - 1].w + 4)
			{
				frame = 50;
				toggleMute();
				return;
			}
			down = true;
			mouseMove(vertical, mx, my);
		}
		else if (button == 5)
			queueVolume(_volume - 0.01f);
		else if (button == 4)
			queueVolume(_volume + 0.01f);
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
			queueVolume((mx - icons[0].w - 8) / 100.0f);
		}
	}

	override void update(Bar bar)
	{
		if (down || queueChange)
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
		ret.fillRect!4(icons[_activeIcon].w + 8, icons[_activeIcon].h / 2 - 1, 102, 1,
				[0xFF, 0xFF, 0xFF, 0xFF]);
		ret.fillRect!4(icons[_activeIcon].w + 8 + cast(int)(abs(_volume) * 100), 0, 2,
				icons[_activeIcon].h, [0xFF, 0xFF, 0xFF, 0xFF]);

		return ret;
	}

private:
	void queueVolume(float volume)
	{
		_volume = volume;
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

	int _activeIcon = 0;
	int frame = 50;
	float _volume;
	IFImage[] icons;
	bool down, queueChange;
	StopWatch changeTimer;
}
