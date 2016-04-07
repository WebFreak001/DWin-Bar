module dwinbar.backend.panel;

import cairo.cairo;
import cairo.c.config;
import cairo.xlib;

import x11.Xutil;
import x11.Xlib;
import x11.X;
import x11.Xatom;

import dwinbar.cairoext;

import dwinbar.widgets.widget;

import dwinbar.backend.xbackend;
import dwinbar.backend.applist;

import std.datetime;
import std.conv;
import core.thread;

static assert(CAIRO_HAS_XLIB_SURFACE);

enum Side : ubyte
{
	Top,
	Right,
	Bottom,
	Left
}

enum Screen : int
{
	First = 0,
	Second,
	Third,
	Fourth
}

struct PanelInfo
{
	int screen;
	int x, y;
	uint width, height;
	Side side = Side.Bottom;

	bool isHorizontal() @property
	{
		return side == Side.Top || side == Side.Bottom;
	}
}

enum dPanelName = "dwin-bar";
char* panelName = cast(char*)(dPanelName ~ "\0").ptr;

class Panel
{
	this(XBackend backend, PanelInfo info)
	{
		x = backend;

		if (info.x == int.min)
		{
			if (info.side == Side.Right)
				info.x = x.screens[info.screen].x + x.screens[info.screen].width - info.width;
			else
				info.x = x.screens[info.screen].x;
		}
		if (info.y == int.min)
		{
			if (info.side == Side.Bottom)
				info.y = x.screens[info.screen].y + x.screens[info.screen].height - info.height;
			else
				info.y = x.screens[info.screen].y;
		}
		if (info.width == 0)
			info.width = x.screens[info.screen].width;
		if (info.height == 0)
			info.height = x.screens[info.screen].height;

		_info = info;
		_dpy = x.display;
		XSetWindowAttributes attr;
		attr.colormap = XCreateColormap(_dpy, x.rootWindow, x.visual, AllocNone);
		attr.border_pixel = 0;
		attr.background_pixel = 0;

		ulong mask = CWEventMask | CWColormap | CWBackPixel | CWBorderPixel;
		_window = XCreateWindow(_dpy, x.rootWindow, info.x, info.y, info.width,
			info.height, 0, x.vinfo.depth, InputOutput, x.visual, mask, &attr);

		setup();

		XMapWindow(_dpy, _window);

		_surface = new XlibSurface(_dpy, _window, x.visual, info.width, info.height);
		_context = Context(_surface);

		_apps = getOpenApps(backend);
		_time = Clock.currStdTime;
	}

	~this()
	{
		_surface.dispose();
		XDestroyWindow(_dpy, _window);
	}

	Window window() @property
	{
		return _window;
	}

	XlibSurface surface() @property
	{
		return _surface;
	}

	Context context() @property
	{
		return _context;
	}

	PanelInfo info() @property
	{
		return _info;
	}

	void handleEvent(ref XEvent e)
	{
		switch (e.type)
		{
		case Expose:
			if (e.xexpose.count < 1)
				paint();
			break;
		case MotionNotify:
			mouseX = e.xmotion.x;
			mouseY = e.xmotion.y;
			if (buttonDown)
			{
				int dx = mouseX - mouseStartX;
				int dy = mouseY - mouseStartY;
				if (dx * dx + dy * dy > 5 * 5)
				{
					isDrag = true;
				}
			}
			break;
		case ButtonPress:
			mouseX = e.xbutton.x;
			mouseY = e.xbutton.y;
			mouseStartX = e.xbutton.x;
			mouseStartY = e.xbutton.y;
			isDrag = false;
			if (e.xbutton.button == 1)
			{
				buttonDown = true;
			}
			break;
		case ButtonRelease:
			mouseX = e.xbutton.x;
			mouseY = e.xbutton.y;
			if (e.xbutton.button == 1)
			{
				buttonDown = false;
				if (!isDrag)
				{
					double length = rhsPadding;
					double lastLen = rhsPadding;
					double currLen = rhsPadding;

					foreach (widget; _widgets)
					{
						lastLen = info.width - rhsOffset - barMargin - length + rhsPadding;
						length += widget.length + rhsPadding;
						currLen = info.width - rhsOffset - barMargin - length + rhsPadding;
						bool hovered = false;
						if (_hasHoverFocus)
						{
							if (_info.isHorizontal)
								hovered = mouseX > currLen && mouseX < lastLen - rhsPadding;
							else
								hovered = mouseY > currLen && mouseY < lastLen - rhsPadding;
						}
						if (hovered)
						{
							if (_info.isHorizontal)
								widget.click(mouseX - currLen);
							else
								widget.click(mouseY - currLen);
							return;
						}
					}

					double pos = appMargin + barMargin;
					foreach (app; _apps)
					{
						if (_hasHoverFocus)
						{
							bool hover = false;
							if (_info.isHorizontal)
								hover = mouseX > pos - 8 && mouseX < pos + appIconSize + 8;
							else
								hover = mouseY > pos && mouseY < pos + appIconSize;

							if (hover)
								x.changeFocus(app.window);
						}
						pos += appMargin + appIconSize;
					}
				}
			}
			break;
		case EnterNotify:
			_hasHoverFocus = true;
			break;
		case LeaveNotify:
			_hasHoverFocus = false;
			break;
		default:
			break;
		}
	}

	void paint()
	{
		// every 0.2s
		if (_time + 2000000 < Clock.currStdTime)
		{
			_time = Clock.currStdTime;

			_apps = getOpenApps(x);

			foreach (widget; _widgets)
				widget.updateLazy();
		}

		context.setOperator(Operator.CAIRO_OPERATOR_OVER);
		context.pushGroup();
		double rhsLength = rhsPadding;

		foreach (widget; _widgets)
			rhsLength += widget.length + rhsPadding;

		if (info.isHorizontal)
			context.roundedRectangle(info.width - rhsOffset - barMargin - rhsLength,
				barMargin, rhsLength, info.height - 2 * barMargin, 2);
		else
			context.roundedRectangle(barMargin,
				info.height - rhsOffset - barMargin - rhsLength,
				info.width - 2 * barMargin, info.height, 2);
		context.setSourceRGBA(0, 0, 0, 0.5);
		context.fill();
		context.setSourceRGB(1, 1, 1);

		double length = rhsPadding;
		double lastLen = rhsPadding;
		double currLen = rhsPadding;

		foreach (widget; _widgets)
		{
			lastLen = info.width - rhsOffset - barMargin - length + rhsPadding;
			length += widget.length + rhsPadding;
			currLen = info.width - rhsOffset - barMargin - length + rhsPadding;
			if (_hasHoverFocus && widget.hasHover())
			{
				if (_info.isHorizontal)
				{
					if (mouseX > currLen && mouseX < lastLen - rhsPadding)
					{
						context.setSourceRGBA(1, 1, 1, 0.1);
						context.rectangle(currLen, barMargin, widget.length,
							info.height - 2 * barMargin);
						context.fill();
						context.setSourceRGB(1, 1, 1);
					}
				}
				else
				{
					if (mouseY > currLen && mouseY < lastLen - rhsPadding)
					{
						context.setSourceRGBA(1, 1, 1, 0.1);
						context.rectangle(barMargin, currLen,
							info.width - 2 * barMargin, widget.length);
						context.fill();
						context.setSourceRGB(1, 1, 1);
					}
				}
			}
			widget.draw(context, currLen);
		}
		double pos = appMargin + barMargin;
		foreach (app; _apps)
		{
			if (_info.isHorizontal)
				context.translate(pos, barMargin - 2);
			else
				context.translate(barMargin, pos - 2);
			if (app.icon && app.icon.nativePointer)
			{
				context.setSourceSurface(app.icon, 0, 0);
				context.rectangle(0, 0, appIconSize, appIconSize);
				context.fill();
			}
			context.identityMatrix();
			switch (app.state)
			{
			case AppState.urgent:
				context.setSourceRGBA(1, 0, 1, 1);
				break;
			case AppState.focused:
				context.setSourceRGBA(1, 1, 1, 0.95);
				break;
			case AppState.visible:
				context.setSourceRGBA(1, 1, 1, 0.45);
				break;
			case AppState.minimized:
			default:
				context.setSourceRGBA(1, 1, 1, 0.2);
				break;
			}
			if (_info.isHorizontal)
				context.roundedRectangle(pos, _info.height - 4, appIconSize, 3, 1.5);
			else
				context.roundedRectangle(barMargin, pos, appIconSize, 3, 1.5);
			context.fill();
			if (_hasHoverFocus)
			{
				bool hover = false;
				if (_info.isHorizontal)
					hover = mouseX > pos - 8 && mouseX < pos + appIconSize + 8;
				else
					hover = mouseY > pos && mouseY < pos + appIconSize;

				if (hover)
				{
					context.setOperator(Operator.CAIRO_OPERATOR_ATOP);
					if (_info.isHorizontal)
						context.rectangle(pos, barMargin - 2, appIconSize, appIconSize);
					else
						context.rectangle(barMargin, pos, appIconSize, appIconSize);
					context.setSourceRGBA(1, 1, 1, 0.15);
					context.fill();
					context.setOperator(Operator.CAIRO_OPERATOR_OVER);
				}
			}
			pos += appMargin + appIconSize;
		}
		context.popGroupToSource();
		context.setOperator(Operator.CAIRO_OPERATOR_SOURCE);
		context.paint();
	}

	void addWidget(Widget widget)
	{
		_widgets ~= widget;
	}

	void sortWidgets()
	{
		import std.algorithm : sort;

		_widgets.sort!((a, b) => a.priority < b.priority);
	}

private:

	void setup()
	{
		XStoreName(_dpy, _window, panelName);
		XSetIconName(_dpy, _window, panelName);

		XChangeProperty(_dpy, _window, XAtom[AtomName._NET_WM_NAME],
			XAtom[AtomName.UTF8_STRING], 8, PropModeReplace,
			cast(ubyte*) panelName, dPanelName.length);

		XChangeProperty(_dpy, _window, XAtom[AtomName._NET_WM_ICON_NAME],
			XAtom[AtomName.UTF8_STRING], 8, PropModeReplace,
			cast(ubyte*) panelName, dPanelName.length);

		long val = cast(long) XAtom[AtomName._NET_WM_WINDOW_TYPE_DOCK];
		XChangeProperty(_dpy, _window, XAtom[AtomName._NET_WM_WINDOW_TYPE],
			XA_ATOM, 32, PropModeReplace, cast(ubyte*)&val, 1);

		val = 0xFFFFFFFF; // All desktops
		XChangeProperty(_dpy, _window, XAtom[AtomName._NET_WM_DESKTOP],
			XA_CARDINAL, 32, PropModeReplace, cast(ubyte*)&val, 1);

		Atom[] state;
		state ~= XAtom[AtomName._NET_WM_STATE_STICKY];
		state ~= XAtom[AtomName._NET_WM_STATE_SKIP_TASKBAR];
		state ~= XAtom[AtomName._NET_WM_STATE_SKIP_PAGER];
		state ~= XAtom[AtomName._NET_WM_STATE_ABOVE];
		XChangeProperty(_dpy, _window, XAtom[AtomName._NET_WM_STATE], XA_ATOM,
			32, PropModeReplace, cast(ubyte*) state.ptr, cast(int) state.length);

		int[5] undecorated = [2, 0, 0, 0, 0];
		XChangeProperty(_dpy, _window, XAtom[AtomName._MOTIF_WM_HINTS],
			XAtom[AtomName._MOTIF_WM_HINTS], 32, PropModeReplace, cast(ubyte*) undecorated.ptr,
			5);

		Atom ver = 5;
		XChangeProperty(_dpy, _window, XAtom[AtomName.XdndAware], XA_ATOM, 32,
			PropModeReplace, cast(ubyte*)&ver, 1);

		XSelectInput(_dpy, _window,
			ExposureMask | EnterWindowMask | LeaveWindowMask | ButtonPressMask | ButtonReleaseMask | KeyPressMask | PointerMotionMask);
		XSetWMProtocols(_dpy, _window, [XAtom[AtomName.WM_DELETE_WINDOW], XAtom[AtomName._NET_WM_PING]].ptr, 2);

		setupStrut();
	}

	void setupStrut()
	{
		long[12] strut = 0;
		if (_info.side == Side.Left)
		{
			strut[0] = _info.width;
			strut[4] = _info.y;
			strut[5] = _info.y + _info.height;
		}
		if (_info.side == Side.Right)
		{
			strut[1] = _info.width;
			strut[6] = _info.y;
			strut[7] = _info.y + _info.height;
		}
		if (_info.side == Side.Top)
		{
			strut[2] = _info.height;
			strut[8] = _info.x;
			strut[9] = _info.x + _info.width;
		}
		if (_info.side == Side.Bottom)
		{
			strut[3] = _info.height;
			strut[10] = _info.x;
			strut[11] = _info.x + _info.width;
		}
		XChangeProperty(_dpy, _window, XAtom[AtomName._NET_WM_STRUT],
			XA_CARDINAL, 32, PropModeReplace, cast(ubyte*) strut.ptr, 4);
		XChangeProperty(_dpy, _window, XAtom[AtomName._NET_WM_STRUT_PARTIAL],
			XA_CARDINAL, 32, PropModeReplace, cast(ubyte*) strut.ptr, 12);
	}

	ulong _time;
	XBackend x;
	Display* _dpy;
	Window _window;
	XlibSurface _surface;
	Context _context;
	PanelInfo _info;
	Widget[] _widgets;
	AppInfo[] _apps;
	bool _hasHoverFocus = false;
	bool isDrag = false;
	bool buttonDown = false;
	int mouseX, mouseY, mouseStartX, mouseStartY;
}
