module dwinbar.widgets.volume;

import dwinbar.widgets.widget;
import dwinbar.backend.panel;
import dwinbar.backend.popup;
import dwinbar.backend.xbackend;
import dwinbar.panels;

import x11.Xlib;
import x11.X;

import cairo.cairo;

import std.datetime;
import std.format;
import std.conv;
import std.regex;
import std.process;

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

class VolumePopup : Popup
{
	this(float volume, XBackend backend, int xPos, int yPos, int contentWidth, int contentHeight)
	{
		_volume = volume;
		_height = contentHeight;
		super(backend, xPos, yPos, contentWidth, contentHeight);
	}

	override void draw(Context context)
	{
		if (_volume < 0)
			_volume = 0;
		if (_volume > 1)
			_volume = 1;
		if (_queueChange && changeTimer.peek.to!("msecs", int) >= 50)
		{
			_queueChange = false;
			changeTimer.stop();
			setVolume(_volume);
		}

		float y = (1 - _volume) * (_height - 16) + 8;
		context.setSourceRGBA(0, 0, 0, 0.54);
		context.rectangle(7, 8, 2, y);
		context.fill();
		context.setSourceRGB(0.11, 0.91, 0.71);
		context.rectangle(7, y, 2, _height - y - 8);
		context.fill();
		context.arc(8, y, 8, 0, 2 * 3.1415926);
		context.fill();
	}

	override void onEvent(ref XEvent e)
	{
		switch (e.type)
		{
		case MotionNotify:
			if (_mouseDown)
			{
				_volume = (e.xmotion.y - 8) / cast(float) _height;
				if (_volume < 0)
					_volume = 0;
				else if (_volume > 1)
					_volume = 1;
				_volume = 1 - _volume;
				_queueChange = true;
				changeTimer.reset();
				changeTimer.start();
			}
			break;
		case ButtonPress:
			if (e.xbutton.button == 1)
			{
				_volume = (e.xbutton.y - 8) / cast(float) _height;
				if (_volume < 0)
					_volume = 0;
				else if (_volume > 1)
					_volume = 1;
				_volume = 1 - _volume;
				_queueChange = true;
				_mouseDown = true;
				changeTimer.reset();
				changeTimer.start();
			}
			break;
		case ButtonRelease:
			if (e.xbutton.button == 1)
				_mouseDown = false;
			break;
		default:
			break;
		}
	}

	float volume()
	{
		return _volume;
	}

private:
	StopWatch changeTimer;
	bool _queueChange;
	bool _mouseDown;
	int _height;
	float _volume;
}

class VolumeWidget : Widget
{
	this(Panels panels, string font, string secFont, PanelInfo panelInfo)
	{
		_panels = panels;
		_font = font;
		_secFont = secFont;
		info = panelInfo;

		_volume = getVolume();

		icons ~= ImageSurface.fromPng("res/icon/volume-low.png");
		icons ~= ImageSurface.fromPng("res/icon/volume-medium.png");
		icons ~= ImageSurface.fromPng("res/icon/volume-high.png");
		icons ~= ImageSurface.fromPng("res/icon/volume-off.png");
	}

	int priority() @property
	{
		return 0;
	}

	double length() @property
	{
		return 32;
	}

	bool hasHover() @property
	{
		return true;
	}

	void click(Panel panel, double len, int panelX, int panelY)
	{
		float vol = _volume = getVolume();
		if (vol < -1)
			return;
		if (vol < 0)
			vol = -vol;
		int x, y;
		Window child;
		XWindowAttributes xwa;
		XTranslateCoordinates(_panels.backend.display, panel.window,
				_panels.backend.rootWindow, 0, 0, &x, &y, &child);
		XGetWindowAttributes(_panels.backend.display, panel.window, &xwa);
		if (_activePopup && !_activePopup.closed)
		{
			_activePopup.close();
			return;
		}
		int popupX = -cast(int)(len - panelX);
		_activePopup = new VolumePopup(vol, _panels.backend, popupX + 16 - 16, y - xwa.y - 160, 16, 150);
		_panels.addPopup(_activePopup);
	}

	void updateLazy()
	{
		_volume = getVolume();
		updateVolume();
	}

	void updateVolume()
	{
		if (_volume < 0)
			_activeIcon = 3;
		else if (_volume <= 0.3f)
			_activeIcon = 0;
		else if (_volume <= 0.6f)
			_activeIcon = 1;
		else if (_volume <= 1)
			_activeIcon = 2;
	}

	void draw(Panel panel, Context context, double start)
	{
		if (_activePopup)
		{
			_volume = _activePopup.volume;
			updateVolume();
		}
		double x, y;
		if (info.isHorizontal)
		{
			x = start + 8;
			y = barMargin + 8;
		}
		else
		{
			x = barMargin + 8;
			y = start + 8;
		}
		context.setSourceSurface(icons[_activeIcon], x, y);
		context.paint();
	}

private:
	int _activeIcon = 0;
	float _volume;
	VolumePopup _activePopup;
	string _font, _secFont;
	PanelInfo info;
	Panels _panels;
	Surface[] icons;
}
