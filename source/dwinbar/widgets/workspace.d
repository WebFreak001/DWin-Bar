module dwinbar.widgets.workspace;

import dwinbar.widgets.widget;

import dwinbar.backend.panel;
import dwinbar.backend.xbackend;

import dwinbar.cairoext;

import cairo.cairo;

import std.format;
import std.string;
import std.conv;

class WorkspaceWidget : Widget
{
	this(XBackend backend, string font, string secFont, PanelInfo panelInfo)
	{
		x = backend;
		_font = font;
		_secFont = secFont;
		info = panelInfo;
	}

	bool hasHover() @property
	{
		return false;
	}

	double length() @property
	{
		return info.isHorizontal ? desktops.length * 32 : 16;
	}

	void click(Panel panel, double len, int panelX, int panelY)
	{
		int desktop = (cast(int) len) / 32;
		if (desktop >= 0 && desktop < desktops.length)
		{
			x.currentWorkspace = desktop;
		}
	}

	void updateLazy()
	{
		if (x.tryGetWorkspaceNames(_desktops))
		{
			_hasNames = true;
		}
		else
		{
			_hasNames = false;
			_desktopLen = x.numWorkspaces;
		}
		_currentDesktop = x.currentWorkspace;
	}

	void draw(Panel panel, Context context, double start)
	{
		context.roundedRectangle(start + _currentDesktop * 32, barMargin, 32, 32, 2);
		context.setSourceRGBA(0, 0, 0, 0.5);
		context.fill();
		context.setSourceRGB(1, 1, 1);
		TextExtents ext;

		foreach (i, desktop; desktops)
		{
			if (i == _currentDesktop)
				context.selectFontFace(_font, FontSlant.CAIRO_FONT_SLANT_NORMAL,
						FontWeight.CAIRO_FONT_WEIGHT_NORMAL);
			else
				context.selectFontFace(_secFont, FontSlant.CAIRO_FONT_SLANT_NORMAL,
						FontWeight.CAIRO_FONT_WEIGHT_NORMAL);
			context.setFontSize(16);
			ext = context.textExtents(desktop);
			context.moveTo(start + i * 32 + 16 - (ext.width / 2 + ext.x_bearing),
					barMargin + 16 - (ext.height / 2 + ext.y_bearing));
			context.showText(desktop);
		}
	}

	string[] desktops() @property
	{
		if (_hasNames)
			return _desktops;
		else
		{
			string[] names;
			for (int i = 0; i < _desktopLen; i++)
				names ~= (i + 1).to!string;
			return names;
		}
	}

private:
	XBackend x;
	string[] _desktops;
	int _desktopLen;
	bool _hasNames = false;
	int _currentDesktop;
	string _font, _secFont;
	PanelInfo info;
	Surface icon;
}
