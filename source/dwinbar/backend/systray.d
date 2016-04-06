module dwinbar.backend.systray;

import dwinbar.backend.xbackend;
import dwinbar.widgets.widget;
import dwinbar.backend.panel;

import std.stdio;

import x11.X;
import x11.Xlib;
import x11.Xatom;

enum Horizontal = 0;
enum Vertical = 1;

enum RequestDock = 0;
enum BeginMessage = 1;
enum CancelMessage = 2;

private __gshared bool error = false;

private extern (C) int trayErrorHandler(Display* display, XErrorEvent* event)
{
	if (event.error_code == 3)
	{
		debug std.stdio.stderr.writeln("Warning: BadWindow error occured");
		return 0;
	}
	char[256] errtext;
	XGetErrorText(display, event.error_code, errtext.ptr, 256);
	std.stdio.stderr.writefln("Failed to dock window (%s): %s", event.error_code, errtext);
	error = true;
	return 0;
}

struct TrayIcon
{
	Window trayWindow;
	Window ownerHandle;
	XBackend backend;

	void moveTo(int x, int y)
	{
		XMoveWindow(backend.display, trayWindow, x, y);
	}
}

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

	bool start(XBackend backend, Panel panel)
	{
		_panel = panel;
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
			dock(event.data.l[2]);
			//_apps ~= fetchWindowInfo!16(x, window);
			break;
		default:
			break;
		}
	}

	auto handle() @property
	{
		return _handle;
	}

	ref TrayIcon[] icons() @property
	{
		return _icons;
	}

private:
	bool dock(Window window)
	{
		std.stdio.writeln("STARTING");
		error = false;
		XErrorHandler old = XSetErrorHandler(cast(XErrorHandler)(&trayErrorHandler));
		XSync(x.display, false);

		ushort pid = 0;
		{
			Atom actual_type;
			int actual_format;
			ulong nitems;
			ulong bytes_after;
			ubyte* prop = null;
			int ret = XGetWindowProperty(x.display, window,
				XAtom[AtomName._NET_WM_PID], 0, 1024, False, AnyPropertyType,
				&actual_type, &actual_format, &nitems, &bytes_after, &prop);
			if (ret == 0 && prop)
			{
				pid = (prop[1] << 8) | prop[0];
			}
		}

		XWindowAttributes attr;
		if (XGetWindowAttributes(x.display, window, &attr) == 0)
		{
			XSync(x.display, false);
			XSetErrorHandler(old);
			return false;
		}

		XSetWindowAttributes setAttr;
		Visual* visual = attr.visual;
		setAttr.background_pixel = 0;
		setAttr.border_pixel = 0;
		setAttr.colormap = attr.colormap;
		auto mask = CWColormap | CWBackPixel | CWBorderPixel;

		TrayIcon icon;
		icon.backend = x;
		icon.ownerHandle = window;
		icon.trayWindow = XCreateWindow(x.display, _panel.window, 0, 0,
			trayIconSize, trayIconSize, 0, attr.depth, InputOutput, visual, mask, &setAttr);

		XMapRaised(x.display, icon.trayWindow);
		XSync(x.display, false);
		XFlush(x.display);
		if (error)
		{
			std.stdio.writeln("FAIL");
			return false;
		}

		XWithdrawWindow(x.display, window, x.screen);
		XReparentWindow(x.display, window, icon.trayWindow, 0, 0);
		XMoveResizeWindow(x.display, window, 0, 0, trayIconSize, trayIconSize);

		{
			XEvent e;
			e.xclient.type = ClientMessage;
			e.xclient.serial = 0;
			e.xclient.send_event = True;
			e.xclient.message_type = XAtom[AtomName._XEMBED];
			e.xclient.window = window;
			e.xclient.format = 32;
			e.xclient.data.l[0] = CurrentTime;
			enum XEMBED_EMBEDDED_NOTIFY = 0;
			e.xclient.data.l[1] = XEMBED_EMBEDDED_NOTIFY;
			e.xclient.data.l[2] = 0;
			e.xclient.data.l[3] = _panel.window;
			e.xclient.data.l[4] = 0;
			XSendEvent(x.display, window, False, NoEventMask, &e);
		}

		XSync(x.display, false);
		XSetErrorHandler(old);

		XFlush(x.display);
		if (error)
		{
			return false;
		}
		_icons ~= icon;
		return true;
	}

	TrayIcon[] _icons;
	Window _handle;
	Panel _panel;
	XBackend x;
}
