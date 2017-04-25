module dwinbar.backend.applist;

import dwinbar.backend.xbackend;
import dwinbar.backend.icongen;
import dwinbar.bar;

import std.algorithm;
import std.array;
import std.range;
import std.string;

import imageformats;

enum AppState
{
	visible,
	minimized,
	urgent
}

struct AppInfo
{
	Window window;
	string title;
	AppState state;
	string iconName;
	IFImage icon;
}

string getWindowTitle(XBackend x, Window window)
{
	XTextProperty prop;
	XGetTextProperty(x.display, window, &prop, XAtom[AtomName._NET_WM_NAME]);
	return cast(string) prop.value[0 .. prop.nitems].dup;
}

struct AppList
{
	// Keep X first because of unions
	XBackend x;

	AppInfo[] infos;

	Window activeWindow;

	alias infos this;

	void updateActive()
	{
		Atom actualType;
		int actualFormat;
		ulong numItems, bytesAfter;
		Window* result;

		scope (exit)
			XFree(result);
		XGetWindowProperty(x.display, x.rootWindow, XAtom[AtomName._NET_ACTIVE_WINDOW],
				0, int.max, false, XA_WINDOW, &actualType, &actualFormat, &numItems,
				&bytesAfter, cast(ubyte**)&result);

		activeWindow = *result;
	}

	void updateClientList(int iconSize)
	{
		Atom actualType;
		int actualFormat;
		ulong numItems, bytesAfter;
		Window* result;

		scope (exit)
			XFree(result);
		XGetWindowProperty(x.display, x.rootWindow, XAtom[AtomName._NET_CLIENT_LIST],
				0, int.max, false, XA_WINDOW, &actualType, &actualFormat, &numItems,
				&bytesAfter, cast(ubyte**)&result);

		Window[] apps = result[0 .. numItems];
		Window[] added;

		XTextProperty prop;

		AppLoop: foreach (app; apps)
		{
			if (updateWindow(app, iconSize))
				added ~= app;
		}

		auto toRemove = infos.map!"a.window".enumerate.array;
		foreach (app; added)
		{
			auto idx = toRemove.countUntil!"a.value == b"(app);
			if (idx != -1)
				toRemove = toRemove.remove(idx);
		}
		foreach_reverse (rem; toRemove)
			infos = infos.remove(rem.index);
	}

	bool updateWindow(Window window, int iconSize)
	{
		Atom actualType;
		int actualFormat;
		ulong numItems, bytesAfter;
		Atom* atomsResult;
		scope (exit)
			XFree(atomsResult);
		if (XGetWindowProperty(x.display, window, XAtom[AtomName._NET_WM_STATE], 0,
				32, false, XA_ATOM, &actualType, &actualFormat, &numItems,
				&bytesAfter, cast(ubyte**)&atomsResult) == Success)
		{
			auto existingIndex = infos.countUntil!"a.window == b"(window);
			AppInfo info;
			info.window = window;
			if (existingIndex != -1)
				info = infos[existingIndex];
			Atom[] atoms = atomsResult[0 .. numItems];
			foreach (atom; atoms)
			{
				if (atom == XAtom[AtomName._NET_WM_STATE_SKIP_TASKBAR])
				{
					if (existingIndex != -1)
						infos = infos.remove(existingIndex);
					return false;
				}
				if (info.state == AppState.visible)
				{
					if (atom == XAtom[AtomName._NET_WM_STATE_HIDDEN])
						info.state = AppState.minimized;
				}
				if (atom == XAtom[AtomName._NET_WM_STATE_DEMANDS_ATTENTION])
					info.state = AppState.urgent;
			}

			info.title = getWindowTitle(x, window);
			XWMHints* hints = XGetWMHints(x.display, window);
			if (hints)
			{
				scope (exit)
					XFree(hints);
				if (hints.flags & XUrgencyHint)
					info.state = AppState.urgent;
			}

			if (existingIndex == -1)
			{
				infos ~= info;
				XSetWindowAttributes attrib;
				attrib.event_mask = PropertyChangeMask;
				XChangeWindowAttributes(x.display, window, CWEventMask, &attrib);
				updateIcon(window, iconSize);
			}
			else
				infos[existingIndex] = info;
			return true;
		}
		else
			return false;
	}

	bool updateIcon(Window window, int targetSize)
	{
		Atom actualType;
		int actualFormat;
		ulong numItems, bytesAfter;
		Atom* result;
		auto existingIndex = infos.countUntil!"a.window == b"(window);
		if (existingIndex == -1)
			return false;
		if (XGetWindowProperty(x.display, window, XAtom[AtomName._NET_WM_ICON], 0,
				uint.max, false, XA_CARDINAL, &actualType, &actualFormat, &numItems,
				&bytesAfter, cast(ubyte**)&result) == Success && numItems > 2)
		{
			ulong[] data = result[0 .. numItems];
			size_t start = findBestIcon(data, targetSize);
			int w = cast(int) data[start];
			int h = cast(int) data[start + 1];
			immutable ulong offset = start + 2;
			ulong[] scaled = scaleImage(targetSize, targetSize, data[offset .. offset + w * h], w, h);
			auto pixels = new ubyte[targetSize * targetSize * 4];
			for (int i = 0; i < targetSize * targetSize; i++)
			{
				immutable ulong color = scaled[i];
				ubyte alpha = (color >> 24) & 0xFF;
				pixels[i * 4 + 0] = (((color >> 0) & 0xFF) * cast(int) alpha / 255) & 0xFF;
				pixels[i * 4 + 1] = (((color >> 8) & 0xFF) * cast(int) alpha / 255) & 0xFF;
				pixels[i * 4 + 2] = (((color >> 16) & 0xFF) * cast(int) alpha / 255) & 0xFF;
				pixels[i * 4 + 3] = alpha;
			}
			infos[existingIndex].icon.w = infos[existingIndex].icon.h = targetSize;
			infos[existingIndex].icon.c = ColFmt.RGBA;
			infos[existingIndex].icon.pixels = pixels;
			return true;
		}
		else
			return false;
	}
}

size_t findBestIcon(ulong[] data, uint targetIconSize)
{
	import std.math;

	if (data.length < 3)
		return 0;

	size_t currentBest = 0;
	ulong currentArea = data[0] * data[1];
	ulong targetArea = (targetIconSize * 2) * (targetIconSize * 2);
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
