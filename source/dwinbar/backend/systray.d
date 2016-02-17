module dwinbar.backend.systray;

import dwinbar.backend.xbackend;
import dwinbar.backend.applist;

import std.stdio;

import x11.X;
import x11.Xlib;
import x11.Xatom;

enum Horizontal = 0;
enum Vertical = 1;

enum RequestDock = 0;
enum BeginMessage = 1;
enum CancelMessage = 2;

class SysTray
{
	private static __gshared tray = new SysTray();

	private this()
	{
	}

	public static SysTray instance()
	{
		return tray;
	}

	bool start(XBackend backend)
	{
		x = backend;
		Window existingTray = XGetSelectionOwner(x.display, x.satom[SpecialAtom.SystemTray]);
		if (existingTray)
		{
			ubyte* prop;
			Atom actualType;
			int actualFormat;
			ulong numItems, bytesAfter;
			ulong* cardResult;
			ushort pid;

			if (XGetWindowProperty(x.display, existingTray,
					XAtom[AtomName._NET_WM_PID], 0, 8, False, AnyPropertyType,
					&actualType, &actualFormat, &numItems, &bytesAfter, &prop) == 0 && prop)
			{
				pid = prop[1] << 8 | prop[0];
				stderr.writefln(
					"Another system tray is already running on window 0x%x on PID %d!",
					existingTray, pid);
			}
			else
			{
				stderr.writefln("Another system tray is already running on window 0x%x!",
					existingTray);
			}
			return false;
		}
		_handle = XCreateSimpleWindow(x.display, x.rootWindow, -1, -1, 1, 1, 0, 0,
			0);

		int orientation = Horizontal;
		XChangeProperty(x.display, _handle,
			XAtom[AtomName._NET_SYSTEM_TRAY_ORIENTATION], XA_CARDINAL, 32,
			PropModeReplace, cast(ubyte*)&orientation, 1);

		XChangeProperty(x.display, _handle,
			XAtom[AtomName._NET_SYSTEM_TRAY_VISUAL], XA_CARDINAL, 32,
			PropModeReplace, cast(ubyte*)&x.vinfo.visualid, 1);

		XSetSelectionOwner(x.display, x.satom[SpecialAtom.SystemTray], _handle, CurrentTime);
		if (XGetSelectionOwner(x.display, x.satom[SpecialAtom.SystemTray]) != _handle)
		{
			stderr.writeln("Could not acquire system tray ownership!");
			return false;
		}

		return true;
	}

	void sendMessage(int message, int data1 = 0, int data2 = 0, int data3 = 0)
	{
		XEvent ev;
		ev.xclient.type = ClientMessage;
		ev.xclient.window = _handle;
		ev.xclient.message_type = XAtom[AtomName._NET_SYSTEM_TRAY_OPCODE];
		ev.xclient.format = 32;
		ev.xclient.data.l[0] = CurrentTime;
		ev.xclient.data.l[1] = message;
		ev.xclient.data.l[2] = data1;
		ev.xclient.data.l[3] = data2;
		ev.xclient.data.l[4] = data3;
		XSendEvent(x.display, _handle, false, NoEventMask, &ev);
	}

	void handleEvent(in XClientMessageEvent event)
	{
		auto op = event.data.l[1];
		switch (op)
		{
		case RequestDock:
			Window window = event.data.l[2];
			_apps ~= fetchWindowInfo!16(x, window);
			break;
		default:
			break;
		}
	}

	auto handle() @property
	{
		return _handle;
	}

	ref AppInfo[] icons() @property
	{
		return _apps;
	}

private:
	AppInfo[] _apps;
	Window _handle;
	XBackend x;
}
