module dwinbar.widgets.clock;

import dwinbar.widgets.widget;
import dwinbar.backend.panel;

import cairo.cairo;

import std.datetime;
import std.format;
import std.conv;

class ClockWidget : Widget
{
	this(string font, string secFont, PanelInfo panelInfo)
	{
		_font = font;
		_secFont = secFont;
		info = panelInfo;

		icon = ImageSurface.fromPng("res/icon/clock.png");
	}

	int priority() @property
	{
		return -1;
	}

	double length() @property
	{
		return info.isHorizontal ? 100 : 16;
	}

	bool hasHover() @property
	{
		return true;
	}

	void click(Panel panel, double len, int panelX, int panelY)
	{
		// TODO: Open clock & time details
	}

	void updateLazy()
	{
	}

	void draw(Panel panel, Context context, double start)
	{
		SysTime clockTime = Clock.currTime;
		string clockMajor = format("%02d:%02d", clockTime.hour, clockTime.minute);
		string clockMinor = format(" %02d", clockTime.second);
		context.selectFontFace(_font, FontSlant.CAIRO_FONT_SLANT_NORMAL,
				FontWeight.CAIRO_FONT_WEIGHT_NORMAL);
		context.setFontSize(16);
		TextExtents ext = context.textExtents(clockMajor);
		double x, y;
		if (info.isHorizontal)
		{
			x = start + 8 + ext.x_bearing;
			y = barMargin + 8;
		}
		else
		{
			x = barMargin + 8 + ext.x_bearing;
			y = start;
		}
		context.moveTo(x + ext.x_bearing, barMargin + 16 - (ext.height / 2 + ext.y_bearing));
		context.showText(clockMajor);
		context.selectFontFace(_secFont, FontSlant.CAIRO_FONT_SLANT_NORMAL,
				FontWeight.CAIRO_FONT_WEIGHT_NORMAL);
		context.moveTo(x + ext.x_bearing + ext.width, barMargin + 16 - (ext.height / 2 + ext.y_bearing));
		context.showText(clockMinor);
		context.setSourceSurface(icon, x + 100 - 24 - 8, y);
		context.paint();
	}

private:
	string _font, _secFont;
	PanelInfo info;
	Surface icon;
}
