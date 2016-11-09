module dwinbar.backend.popup;

import cairo.cairo;
import cairo.xlib;

import x11.Xutil;
import x11.Xlib;
import x11.X;
import x11.Xatom;

static import std.stdio;

import dwinbar.cairoext;

import dwinbar.backend.xbackend;

enum dPopupName = "dwin-bar-popup";
char* popupName = cast(char*)(dPopupName ~ '\0').ptr;

abstract class Popup
{
	this(XBackend backend, int xPos, int yPos, int contentWidth, int contentHeight)
	{
		x = backend;

		_contentWidth = contentWidth;
		_contentHeight = contentHeight;

		XSetWindowAttributes attr;
		attr.colormap = XCreateColormap(x.display, x.rootWindow, x.visual, AllocNone);
		attr.border_pixel = 0;
		attr.background_pixel = 0;

		ulong mask = CWEventMask | CWColormap | CWBackPixel | CWBorderPixel;
		_window = XCreateWindow(x.display, x.rootWindow, xPos, yPos,
				contentWidth + 16, contentHeight + 24, 0, x.vinfo.depth, InputOutput,
				x.visual, mask, &attr);

		setup(contentWidth + 16, contentHeight + 24);

		XMapWindow(x.display, _window);

		std.stdio.writeln("Mapped window");

		_surface = new XlibSurface(x.display, _window, x.visual, contentWidth + 16, contentHeight + 24);
		_context = Context(_surface);
	}

	void handleEvent(ref XEvent e)
	{
		switch (e.type)
		{
		case Expose:
			if (e.xexpose.count < 1)
				paint();
			break;
		case KeyPress:
			if (e.xkey.keycode == 9) // esc
			{
				close();
			}
			break;
		default:
			onEvent(e);
			break;
		}
	}

	void paint()
	{
		_context.setOperator(Operator.CAIRO_OPERATOR_OVER);
		_context.pushGroup();
		_context.setSourceRGB(0.96, 0.96, 0.96);
		_context.roundedRectangle(0, 0, _contentWidth + 16, _contentHeight + 16, 4);
		_context.fill();
		_context.moveTo(_contentWidth - 8, _contentHeight + 16);
		_context.lineTo(_contentWidth, _contentHeight + 24);
		_context.lineTo(_contentWidth + 8, _contentHeight + 16);
		_context.fill();
		_context.translate(8, 8);
		draw(_context);
		_context.popGroupToSource();
		_context.setOperator(Operator.CAIRO_OPERATOR_SOURCE);
		_context.paint();
	}

	abstract void draw(Context context);
	abstract void onEvent(ref XEvent e);

	void close()
	{
		XUnmapWindow(x.display, _window);
		closed = true;
	}

	Window window()
	{
		return _window;
	}

	bool closed;

private:

	void setup(int width, int height)
	{
		XStoreName(x.display, _window, popupName);
		XSetIconName(x.display, _window, popupName);

		XChangeProperty(x.display, _window, XAtom[AtomName._NET_WM_NAME],
				XAtom[AtomName.UTF8_STRING], 8, PropModeReplace,
				cast(ubyte*) popupName, dPopupName.length);

		XChangeProperty(x.display, _window, XAtom[AtomName._NET_WM_ICON_NAME],
				XAtom[AtomName.UTF8_STRING], 8, PropModeReplace,
				cast(ubyte*) popupName, dPopupName.length);

		long val = cast(long) XAtom[AtomName._NET_WM_WINDOW_TYPE_MENU];
		XChangeProperty(x.display, _window, XAtom[AtomName._NET_WM_WINDOW_TYPE],
				XA_ATOM, 32, PropModeReplace, cast(ubyte*)&val, 1);

		val = 0xFFFFFFFF; // All desktops
		XChangeProperty(x.display, _window, XAtom[AtomName._NET_WM_DESKTOP],
				XA_CARDINAL, 32, PropModeReplace, cast(ubyte*)&val, 1);

		Atom[] state;
		state ~= XAtom[AtomName._NET_WM_STATE_STICKY];
		state ~= XAtom[AtomName._NET_WM_STATE_SKIP_TASKBAR];
		state ~= XAtom[AtomName._NET_WM_STATE_SKIP_PAGER];
		state ~= XAtom[AtomName._NET_WM_STATE_ABOVE];
		XChangeProperty(x.display, _window, XAtom[AtomName._NET_WM_STATE], XA_ATOM,
				32, PropModeReplace, cast(ubyte*) state.ptr, cast(int) state.length);

		int[5] undecorated = [2, 0, 0, 0, 0];
		XChangeProperty(x.display, _window, XAtom[AtomName._MOTIF_WM_HINTS],
				XAtom[AtomName._MOTIF_WM_HINTS], 32, PropModeReplace, cast(ubyte*) undecorated.ptr, 5);

		XSelectInput(x.display, _window, ExposureMask | EnterWindowMask | LeaveWindowMask
				| ButtonPressMask | ButtonReleaseMask | KeyPressMask | PointerMotionMask);
		XSetWMProtocols(x.display, _window, [XAtom[AtomName.WM_DELETE_WINDOW],
				XAtom[AtomName._NET_WM_PING]].ptr, 2);

		XClassHint clazz;
		clazz.res_name = popupName;
		clazz.res_class = popupName;
		XWMHints wh;
		XSizeHints size;
		size.width = size.base_width = size.max_width = size.min_width = width;
		size.height = size.base_height = size.max_height = size.min_height = height;
		XSetWMProperties(x.display, _window, null, null, null, 0, &size, &wh, &clazz);
	}

	Window _window;
	Surface _surface;
	Context _context;
	int _contentWidth, _contentHeight;
	XBackend x;
}
