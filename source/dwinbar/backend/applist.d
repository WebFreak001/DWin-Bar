module dwinbar.backend.applist;

import x11.Xutil;
import x11.Xlib;
import x11.X;
import x11.Xatom;

import cairo.cairo;

import dwinbar.widgets.widget;

import dwinbar.backend.xbackend;
import dwinbar.backend.icongen;

import std.algorithm;
import std.string;

enum AppState
{
	focused,
	visible,
	minimized,
	urgent
}

struct AppInfo
{
	Window window;
	string title;
	AppState state;
	Surface icon;
	ubyte[] pixels;
}

enum Success = 0;

AppInfo[Window] cache;

AppInfo[] getOpenApps(XBackend backend)
{
	Atom actualType;
	int actualFormat;
	ulong numItems, bytesAfter;
	Window* result;
	Atom* atomsResult;
	ulong* cardResult;

	scope (exit)
		XFree(result);
	XGetWindowProperty(backend.display, backend.rootWindow,
		XAtom[AtomName._NET_CLIENT_LIST], 0, int.max, false, XA_WINDOW,
		&actualType, &actualFormat, &numItems, &bytesAfter, cast(ubyte**)&result);

	Window[] apps = result[0 .. numItems];
	foreach_reverse (win; cache.keys)
	{
		if (!apps.canFind(win))
		{
			cache[win].icon.dispose();
			cache.remove(win);
		}
	}

	Window focused;
	int revert_to;

	XGetInputFocus(backend.display, &focused, &revert_to);

	XTextProperty prop;

	AppInfo[] infos;

	AppLoop: foreach (app; apps)
	{
		scope (exit)
			XFree(atomsResult);
		if (XGetWindowProperty(backend.display, app,
				XAtom[AtomName._NET_WM_STATE], 0, 32, false, XA_ATOM,
				&actualType, &actualFormat, &numItems, &bytesAfter,
				cast(ubyte**)&atomsResult) == Success)
		{
			XGetTextProperty(backend.display, app, &prop, XAtom[AtomName._NET_WM_NAME]);
			AppInfo info;
			if ((app in cache)!is null)
				info = cache[app];
			info.window = app;
			info.title = cast(string) prop.value[0 .. prop.nitems].dup;
			info.state = AppState.visible;
			if (focused == app)
				info.state = AppState.focused;
			Atom[] atoms = atomsResult[0 .. numItems];
			foreach (atom; atoms)
			{
				if (atom == XAtom[AtomName._NET_WM_STATE_SKIP_TASKBAR])
					continue AppLoop;
				if (info.state == AppState.visible)
				{
					if (atom == XAtom[AtomName._NET_WM_STATE_HIDDEN])
						info.state = AppState.minimized;
					else if (atom == XAtom[AtomName._NET_WM_STATE_FOCUSED])
						info.state = AppState.focused;
				}
				if (atom == XAtom[AtomName._NET_WM_STATE_DEMANDS_ATTENTION])
					info.state = AppState.urgent;
			}

			XWMHints* hints = XGetWMHints(backend.display, app);
			if (hints)
			{
				scope (exit)
					XFree(hints);
				if (hints.flags & XUrgencyHint)
					info.state = AppState.urgent;
			}

			if ((app in cache) is null)
			{
				if (XGetWindowProperty(backend.display, app,
						XAtom[AtomName._NET_WM_ICON], 0, uint.max, false,
						XA_CARDINAL, &actualType, &actualFormat, &numItems,
						&bytesAfter, cast(ubyte**)&cardResult) == Success && numItems > 2)
				{
					ulong[] data = cardResult[0 .. numItems];
					size_t start = findBestIcon(data);
					ulong width = data[start];
					ulong height = data[start + 1];
					auto stride = formatStrideForWidth(Format.CAIRO_FORMAT_ARGB32,
						appIconSize);
					ulong offset = start + 2;
					ulong[] scaled = scaleImage(appIconSize, appIconSize,
						data[offset .. offset + width * height], cast(int) width, cast(int) height);
					info.pixels = new ubyte[stride * appIconSize];
					for (int i = 0; i < appIconSize * appIconSize; i++)
					{
						ulong color = scaled[i];
						info.pixels[i * 4 + 0] = (color >> 0) & 0xFF;
						info.pixels[i * 4 + 1] = (color >> 8) & 0xFF;
						info.pixels[i * 4 + 2] = (color >> 16) & 0xFF;
						info.pixels[i * 4 + 3] = (color >> 24) & 0xFF;
					}
					info.icon = new ImageSurface(info.pixels,
						Format.CAIRO_FORMAT_ARGB32, appIconSize, appIconSize, stride);
				}
			}

			cache[app] = info;
			infos ~= info;
		}
	}

	return infos;
}

size_t findBestIcon(ulong[] data)
{
	import std.math;

	size_t currentBest = 0;
	ulong currentArea = data[0] * data[1];
	enum targetArea = (appIconSize * 2) * (appIconSize * 2);
	size_t cursor = 2 + currentArea;
	while (cursor < data.length)
	{
		ulong selectedArea = data[cursor] * data[cursor + 1];
		if (abs(targetArea - selectedArea) <= abs(targetArea - currentArea))
		{
			currentBest = cursor;
		}
		cursor += 2 + selectedArea;
	}
	return currentBest;
}
