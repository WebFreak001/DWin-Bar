module dwinbar.widgets.tray;

import dwinbar.widgets.widget;

import dwinbar.backend.panel;
import dwinbar.backend.systray;

import cairo.cairo;

import std.datetime;
import std.format;
import std.conv;
import std.math;

class TrayWidget : Widget
{
	this(string font, string secFont, PanelInfo panelInfo)
	{
		_font = font;
		_secFont = secFont;
		info = panelInfo;
	}

	int priority() @property
	{
		return 10;
	}

	double length() @property
	{
		return info.isHorizontal ? (
			cast(int) SysTray.instance.icons.length * (
			trayIconSize + trayHorizontalMargin) - trayHorizontalMargin) : 16;
	}

	bool hasHover() @property
	{
		return true;
	}

	void click(Panel panel, double len, int panelX, int panelY)
	{
	}

	void updateLazy()
	{
	}

	void draw(Panel panel, Context context, double start)
	{
		int cur = cast(int) round(start);
		if (cur != prevStart || SysTray.instance.icons.length != oldLength)
		{
			oldLength = SysTray.instance.icons.length;
			prevStart = cur;
			foreach (i, TrayIcon icon; SysTray.instance.icons)
			{
				icon.moveTo(cur + cast(int) i * (trayIconSize + trayHorizontalMargin), trayVerticalMargin);
			}
		}
	}

private:
	size_t oldLength;
	int prevStart = 0;
	string _font, _secFont;
	PanelInfo info;
}
