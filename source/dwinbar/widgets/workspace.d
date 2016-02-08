module dwinbar.widgets.workspace;

import dwinbar.widgets.widget;

import dwinbar.backend.panel;
import dwinbar.backend.xbackend;

import dwinbar.cairoext;

import x11.X;
import x11.Xlib;
import x11.Xatom;

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

	int priority() @property
	{
		return 100;
	}

	bool hasHover() @property
	{
		return false;
	}

	double length() @property
	{
		return info.isHorizontal ? desktops.length * 32 : 16;
	}

	void click(double len)
	{
		int desktop = (cast(int) len) / 32;
		if (desktop >= 0 && desktop < desktops.length)
		{
			XChangeProperty(x.display, x.rootWindow,
				XAtom[AtomName._NET_CURRENT_DESKTOP], XA_CARDINAL, 32,
				PropModeReplace, cast(ubyte*)&desktop, 1);
		}
	}

	void updateLazy()
	{
		Atom returnType;
		int format;
		ulong number, bytesAfter;
		uint* cardinal;
		ubyte* strs;

		if (XGetWindowProperty(x.display, x.rootWindow,
				XAtom[AtomName._NET_DESKTOP_NAMES], 0, 64, false,
				AnyPropertyType, &returnType, &format, &number,
				&bytesAfter, cast(ubyte**)&strs) == 0 && format == 8)
		{
			_desktops = (cast(string) strs[0 .. number].idup).split('\0')[0 .. $ - 1];
			_hasNames = true;
		}
		else
		{
			_hasNames = false;
			XGetWindowProperty(x.display, x.rootWindow,
				XAtom[AtomName._NET_NUMBER_OF_DESKTOPS], 0, 1, false,
				XA_CARDINAL, &returnType, &format, &number, &bytesAfter,
				cast(ubyte**)&cardinal);
			_desktopLen = cardinal[0];
		}
		XGetWindowProperty(x.display, x.rootWindow,
			XAtom[AtomName._NET_CURRENT_DESKTOP], 0, 1, false, XA_CARDINAL,
			&returnType, &format, &number, &bytesAfter, cast(ubyte**)&cardinal);
		_currentDesktop = cardinal[0];
	}

	void draw(Context context, double start)
	{
		context.roundedRectangle(start + _currentDesktop * 32, barMargin, 32, 32, 2);
		context.setSourceRGBA(0, 0, 0, 0.5);
		context.fill();
		context.setSourceRGB(1, 1, 1);
		TextExtents ext;

		foreach (i, desktop; desktops)
		{
			if (i == _currentDesktop)
				context.selectFontFace(_font,
					FontSlant.CAIRO_FONT_SLANT_NORMAL, FontWeight.CAIRO_FONT_WEIGHT_NORMAL);
			else
				context.selectFontFace(_secFont,
					FontSlant.CAIRO_FONT_SLANT_NORMAL, FontWeight.CAIRO_FONT_WEIGHT_NORMAL);
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
