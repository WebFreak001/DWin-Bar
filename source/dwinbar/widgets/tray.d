module dwinbar.widgets.tray;

import dwinbar.widgets.widget;

import dwinbar.backend.panel;
import dwinbar.backend.systray;

import cairo.cairo;

import std.datetime;
import std.format;
import std.conv;

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
		return info.isHorizontal ? 100 : 16;
	}

	bool hasHover() @property
	{
		return true;
	}

	void click(double len)
	{
	}

	void updateLazy()
	{
	}

	void draw(Context context, double start)
	{
		foreach (icon; SysTray.instance.icons)
		{
			context.translate(start, appMargin);
			if (icon.icon && icon.icon.nativePointer)
				context.setSourceSurface(icon.icon, 0, 0);
			context.rectangle(0, 0, 16, 16);
			context.fill();
			context.identityMatrix();
		}
	}

private:
	string _font, _secFont;
	PanelInfo info;
}
