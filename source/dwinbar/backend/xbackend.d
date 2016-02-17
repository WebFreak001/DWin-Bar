module dwinbar.backend.xbackend;

import std.string;
import std.traits;
import std.conv;

import core.thread;

import x11.Xutil;
import x11.Xlib;
import x11.extensions.Xrandr;
import x11.X;
import x11.Xatom;

struct XineramaScreenInfo
{
	int screen_number;
	short x_org;
	short y_org;
	short width;
	short height;
}

extern (C) bool XineramaIsActive(Display* dpy);
extern (C) XineramaScreenInfo* XineramaQueryScreens(Display* dpy, int* number);

extern (C) int errorHandler(Display* display, XErrorEvent* event)
{
	if (event.error_code == 3)
	{
		debug std.stdio.stderr.writeln("Warning: BadWindow error occured");
		return 0;
	}
	char[256] errtext;
	XGetErrorText(display, event.error_code, errtext.ptr, 256);
	std.stdio.stderr.writefln("an XError occured (%s): %s", event.error_code, errtext);
	throw new Exception("");
}

enum AtomName : string
{
	WM_DELETE_WINDOW = "WM_DELETE_WINDOW",
	WM_PROTOCOLS = "WM_PROTOCOLS",
	_XROOTPMAP_ID = "_XROOTPMAP_ID",
	_XROOTMAP_ID = "_XROOTMAP_ID",
	_NET_CURRENT_DESKTOP = "_NET_CURRENT_DESKTOP",
	_NET_NUMBER_OF_DESKTOPS = "_NET_NUMBER_OF_DESKTOPS",
	_NET_DESKTOP_NAMES = "_NET_DESKTOP_NAMES",
	_NET_DESKTOP_GEOMETRY = "_NET_DESKTOP_GEOMETRY",
	_NET_DESKTOP_VIEWPORT = "_NET_DESKTOP_VIEWPORT",
	_NET_WORKAREA = "_NET_WORKAREA",
	_NET_ACTIVE_WINDOW = "_NET_ACTIVE_WINDOW",
	_NET_WM_WINDOW_TYPE = "_NET_WM_WINDOW_TYPE",
	_NET_WM_STATE_SKIP_PAGER = "_NET_WM_STATE_SKIP_PAGER",
	_NET_WM_STATE_SKIP_TASKBAR = "_NET_WM_STATE_SKIP_TASKBAR",
	_NET_WM_STATE_STICKY = "_NET_WM_STATE_STICKY",
	_NET_WM_STATE_DEMANDS_ATTENTION = "_NET_WM_STATE_DEMANDS_ATTENTION",
	_NET_WM_WINDOW_TYPE_DOCK = "_NET_WM_WINDOW_TYPE_DOCK",
	_NET_WM_WINDOW_TYPE_DESKTOP = "_NET_WM_WINDOW_TYPE_DESKTOP",
	_NET_WM_WINDOW_TYPE_TOOLBAR = "_NET_WM_WINDOW_TYPE_TOOLBAR",
	_NET_WM_WINDOW_TYPE_MENU = "_NET_WM_WINDOW_TYPE_MENU",
	_NET_WM_WINDOW_TYPE_SPLASH = "_NET_WM_WINDOW_TYPE_SPLASH",
	_NET_WM_WINDOW_TYPE_DIALOG = "_NET_WM_WINDOW_TYPE_DIALOG",
	_NET_WM_WINDOW_TYPE_NORMAL = "_NET_WM_WINDOW_TYPE_NORMAL",
	_NET_WM_DESKTOP = "_NET_WM_DESKTOP",
	WM_STATE = "WM_STATE",
	_NET_WM_STATE = "_NET_WM_STATE",
	_NET_WM_STATE_MAXIMIZED_VERT = "_NET_WM_STATE_MAXIMIZED_VERT",
	_NET_WM_STATE_MAXIMIZED_HORZ = "_NET_WM_STATE_MAXIMIZED_HORZ",
	_NET_WM_STATE_SHADED = "_NET_WM_STATE_SHADED",
	_NET_WM_STATE_HIDDEN = "_NET_WM_STATE_HIDDEN",
	_NET_WM_STATE_BELOW = "_NET_WM_STATE_BELOW",
	_NET_WM_STATE_ABOVE = "_NET_WM_STATE_ABOVE",
	_NET_WM_STATE_MODAL = "_NET_WM_STATE_MODAL",
	_NET_WM_STATE_FOCUSED = "_NET_WM_STATE_FOCUSED",
	_NET_CLIENT_LIST = "_NET_CLIENT_LIST",
	_NET_CLIENT_LIST_STACKING = "_NET_CLIENT_LIST_STACKING",
	_NET_WM_VISIBLE_NAME = "_NET_WM_VISIBLE_NAME",
	_NET_WM_NAME = "_NET_WM_NAME",
	_NET_WM_STRUT = "_NET_WM_STRUT",
	_NET_WM_ICON = "_NET_WM_ICON",
	_NET_WM_ICON_GEOMETRY = "_NET_WM_ICON_GEOMETRY",
	_NET_WM_ICON_NAME = "_NET_WM_ICON_NAME",
	_NET_CLOSE_WINDOW = "_NET_CLOSE_WINDOW",
	UTF8_STRING = "UTF8_STRING",
	_NET_SUPPORTING_WM_CHECK = "_NET_SUPPORTING_WM_CHECK",
	_NET_WM_STRUT_PARTIAL = "_NET_WM_STRUT_PARTIAL",
	WM_NAME = "WM_NAME",
	__SWM_VROOT = "__SWM_VROOT",
	_MOTIF_WM_HINTS = "_MOTIF_WM_HINTS",
	WM_HINTS = "WM_HINTS",
	_XSETTINGS_SETTINGS = "_XSETTINGS_SETTINGS",
	_NET_SYSTEM_TRAY_OPCODE = "_NET_SYSTEM_TRAY_OPCODE",
	MANAGER = "MANAGER",
	_NET_SYSTEM_TRAY_MESSAGE_DATA = "_NET_SYSTEM_TRAY_MESSAGE_DATA",
	_NET_SYSTEM_TRAY_ORIENTATION = "_NET_SYSTEM_TRAY_ORIENTATION",
	_NET_SYSTEM_TRAY_ICON_SIZE = "_NET_SYSTEM_TRAY_ICON_SIZE",
	_NET_SYSTEM_TRAY_PADDING = "_NET_SYSTEM_TRAY_PADDING",
	_NET_SYSTEM_TRAY_VISUAL = "_NET_SYSTEM_TRAY_VISUAL",
	_XEMBED = "_XEMBED",
	_XEMBED_INFO = "_XEMBED_INFO",
	_NET_WM_PID = "_NET_WM_PID",
	XdndAware = "XdndAware",
	XdndEnter = "XdndEnter",
	XdndPosition = "XdndPosition",
	XdndStatus = "XdndStatus",
	XdndDrop = "XdndDrop",
	XdndLeave = "XdndLeave",
	XdndSelection = "XdndSelection",
	XdndTypeList = "XdndTypeList",
	XdndActionCopy = "XdndActionCopy",
	XdndFinished = "XdndFinished",
	TARGETS = "TARGETS",
}

enum SpecialAtom
{
	SystemTray = 0
}

struct ScreenInfo
{
	short x, y, width, height;
}

static Atom[AtomName] XAtom;

enum Success = 0;

class XBackend
{
	this(char* displayName = null)
	{
		_display = XOpenDisplay(displayName);

		if (_display is null)
			throw new Exception("Could not open display");

		_screen = XDefaultScreen(_display);
		if (_screen < 0)
			throw new Exception("Could not open screen");
		_root = XRootWindow(_display, _screen);

		XMatchVisualInfo(_display, _screen, 32, TrueColor, &_vinfo);

		foreach (name; EnumMembers!AtomName)
		{
			XAtom[name] = XInternAtom(_display, name.toStringz(), false);
			assert(XAtom[name], "No such atom: " ~ name);
			debug std.stdio.writeln("Atom ", XAtom[name], " = ", name);
		}

		XSetErrorHandler(cast(XErrorHandler)(&errorHandler));

		_atoms = new Atom[SpecialAtom.max + 1];
		_atoms[SpecialAtom.SystemTray] = XInternAtom(_display,
			("_NET_SYSTEM_TRAY_S" ~ _screen.to!string).toStringz, false);

		foreach (i, atom; _atoms)
			assert(atom, "No such special atom: " ~ (cast(SpecialAtom) i).to!string);

		loadScreens();
	}

	~this()
	{
		XCloseDisplay(_display);
	}

	Display* display() @property
	{
		return _display;
	}

	int screen() @property
	{
		return _screen;
	}

	Window rootWindow() @property
	{
		return _root;
	}

	XVisualInfo vinfo() @property
	{
		return _vinfo;
	}

	Visual* visual() @property
	{
		return _vinfo.visual;
	}

	ScreenInfo[] screens() @property
	{
		return _screens;
	}

	void changeFocus(Window window)
	{
		XChangeProperty(_display, _root, XAtom[AtomName._NET_ACTIVE_WINDOW],
			XA_WINDOW, 32, PropModeReplace, cast(ubyte*)&window, 1);
		XSetInputFocus(_display, window, RevertToNone, CurrentTime);
	}

	uint currentWorkspace() @property
	{
		Atom returnType;
		int format;
		ulong number, bytesAfter;
		uint* cardinal;
		assert(XGetWindowProperty(_display, _root,
			XAtom[AtomName._NET_CURRENT_DESKTOP], 0, 1, false, XA_CARDINAL,
			&returnType, &format, &number, &bytesAfter, cast(ubyte**)&cardinal) == Success);
		return cardinal[0];
	}

	void currentWorkspace(uint value) @property
	{
		assert(XChangeProperty(_display, _root,
			XAtom[AtomName._NET_CURRENT_DESKTOP], XA_CARDINAL, 32,
			PropModeReplace, cast(ubyte*)&value, 1) == Success);
	}

	uint numWorkspaces() @property
	{
		Atom returnType;
		int format;
		ulong number, bytesAfter;
		uint* cardinal;
		assert(XGetWindowProperty(_display, _root,
			XAtom[AtomName._NET_NUMBER_OF_DESKTOPS], 0, 1, false, XA_CARDINAL,
			&returnType, &format, &number, &bytesAfter, cast(ubyte**)&cardinal) == Success);
		return cardinal[0];
	}

	bool tryGetWorkspaceNames(out string[] names)
	{
		Atom returnType;
		int format;
		ulong number, bytesAfter;
		ubyte* strs;

		if (XGetWindowProperty(_display, _root,
				XAtom[AtomName._NET_DESKTOP_NAMES], 0, 64, false,
				AnyPropertyType, &returnType, &format, &number,
				&bytesAfter, cast(ubyte**)&strs) == 0 && format == 8)
		{
			names = (cast(string) strs[0 .. number].idup).split('\0')[0 .. $ - 1];
			return true;
		}
		return false;
	}

	auto satom() @property
	{
		return _atoms;
	}

private:
	void loadScreens()
	{
		if (XineramaIsActive(_display))
		{
			int numScreens;
			XineramaScreenInfo[] infos = XineramaQueryScreens(_display, &numScreens)[0 .. numScreens];
			scope (exit)
				XFree(infos.ptr);

			if (infos.length <= 0)
			{
				fallbackScreen();
				return;
			}

			foreach (info; infos)
			{
				_screens ~= ScreenInfo(info.x_org, info.y_org, info.width, info.height);
			}
		}
		else
			fallbackScreen();
	}

	void fallbackScreen()
	{
		uint d1, screenWidth, screenHeight;
		Window d2;
		int d3;
		XGetGeometry(_display, _root, &d2, &d3, &d3, &screenWidth, &screenHeight, &d1,
			&d1);

		_screens ~= ScreenInfo(0, 0, cast(short) screenWidth, cast(short) screenHeight);
	}

	Atom[] _atoms;
	ScreenInfo[] _screens;
	Display* _display;
	int _screen;
	Window _root;
	XVisualInfo _vinfo;
}
