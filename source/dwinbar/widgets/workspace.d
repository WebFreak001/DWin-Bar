module dwinbar.widgets.workspace;

import dwinbar.widget;
import dwinbar.bar;

import dwinbar.backend.xbackend;

import std.datetime;
import std.format;
import std.conv;

class WorkspaceWidget : Widget, IPropertyWatch, IMouseWatch
{
	this(XBackend x)
	{
		this.x = x;
		x.tryGetWorkspaceNames(desktops);
	}

	override int width(bool) const
	{
		return cast(int) desktops.length * 32;
	}

	override int height(bool) const
	{
		return 16;
	}

	override bool hasHover() @property
	{
		return false;
	}

	override IFImage redraw(bool vertical, Bar bar, bool hovered)
	{
		IFImage ret;
		ret.w = width(vertical);
		ret.h = height(vertical);
		ret.c = ColFmt.RGBA;
		ret.pixels.length = ret.w * ret.h * ret.c;
		ret.pixels[] = 0;

		foreach (i, desktop; desktops)
		{
			auto font = bar.faceSecondary;
			if (i == currentWorkspace)
				font = bar.facePrimary;
			auto size = measureText(font, desktop);
			ret.drawText(font, desktop, i * 32 + 16 - size[0] / 2, 14,
					cast(ubyte[4])[0xFF, 0xFF, 0xFF, 0xFF]);
		}

		return ret;
	}

	override void update(Bar)
	{
	}

	override void onPropertyChange(Window window, Atom property)
	{
		if (window == x.rootWindow)
		{
			if (property == XAtom[AtomName._NET_DESKTOP_NAMES])
			{
				x.tryGetWorkspaceNames(desktops);
				queueRedraw();
			}
			else if (property == XAtom[AtomName._NET_CURRENT_DESKTOP])
			{
				currentWorkspace = x.currentWorkspace;
				queueRedraw();
			}
		}
	}

	void mouseDown(bool vertical, int mx, int my, int button)
	{
		if (button == 5)
			changeTo(currentWorkspace + 1);
		else if (button == 4)
			changeTo(currentWorkspace - 1);
		if (button != 1)
			return;
		int desktop = (cast(int) mx) / 32;
		changeTo(desktop);
	}

	void mouseUp(bool vertical, int x, int y, int button)
	{
	}

	void mouseMove(bool vertical, int x, int y)
	{
	}

private:
	void changeTo(uint desktop)
	{
		if (desktop >= 0 && desktop < desktops.length)
		{
			if (x.i3.available)
				x.i3.sendCommand("workspace " ~ desktops[desktop]);
			else
				x.currentWorkspace = desktop;
		}
	}

	XBackend x;
	string[] desktops;
	uint currentWorkspace;
}
