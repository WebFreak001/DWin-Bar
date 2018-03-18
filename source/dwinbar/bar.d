module dwinbar.bar;

import derelict.freetype.ft;

import dwinbar.backend.xbackend;
import dwinbar.backend.icongen;

import dwinbar.widget;

import std.algorithm;
import std.conv;
import std.file;
import std.path;
import std.process;
import std.range;
import std.string;

static import std.stdio;

import core.thread;
import x11.Xatom;
import dwinbar.backend.applist;

struct BarConfiguration
{
	string fontPrimary = "Roboto-Medium";
	string fontSecondary = "Roboto-Light";
	string fontNeutral = "Roboto-Regular";
	string fontFallback = "NotoSans-Regular";
	char* displayName = null;
}

struct PanelConfiguration
{
	int height = 38;
	int barBaselinePadding = 16;
	int appIconPadding = 4;
	int appBaselineMargin = 8;
	int widgetBaselineMargin = 16;
	int focusStripeHeight = 2;
	int offsetX = 0;
	int offsetY = 0;
	bool enableAppList = true;

	int iconSize() @property const
	{
		return height.iconSizeForHeight;
	}
}

int iconSizeForHeight(int height)
{
	if (height - 6 > 256)
		return 256;
	return height - 6;
}

enum Dock : ubyte
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

struct PositionedWidget
{
	Widget widget;
	int x, y, w, h;

	alias widget this;

	bool contains(int dx, int dy, int dw = 0, int dh = 0)
	{
		return !(x > dx + dw || x + w <= dx || y > dy + dh || y + h <= dy);
	}

	bool isHovered(int mx, int margin)
	{
		return mx > x - margin / 2 && mx <= x + w + margin / 2;
	}
}

struct WidgetManager
{
	this(bool vertical, int width, PanelConfiguration config)
	{
		this.vertical = vertical;
		this.width = width;
		this.height = config.height;
		this.config = config;
		x = width - config.barBaselinePadding;
	}

	void regen()
	{
		x = width - config.barBaselinePadding;
		foreach (ref widget; widgets)
		{
			widget.x = x - widget.w;
			x -= widget.w + config.widgetBaselineMargin;
		}
	}

	void add(Widget widget)
	{
		PositionedWidget positioned;
		positioned.widget = widget;
		positioned.w = widget.width(vertical);
		positioned.h = widget.height(vertical);
		positioned.x = x - positioned.w;
		positioned.y = (height - positioned.h) / 2;
		widgets ~= positioned;
		x -= positioned.w + config.widgetBaselineMargin;
	}

	bool vertical;
	int width, height, x;
	PanelConfiguration config;
	PositionedWidget[] widgets;

	alias widgets this;
}

enum dPanelName = "dwin-bar";
char* panelName = cast(char*)(dPanelName ~ '\0').ptr;

struct Panel
{
	int index;
	Screen screen;
	Dock dock;
	int winX, winY;
	int winWidth, winHeight;
	Window window;
	GC gc;
	union
	{
		XBackend x;
		AppList apps;
	}

	WidgetManager widgets;
	int height;
	PanelConfiguration config;
	IFImage background;
	IFImage defaultAppIcon;
	XImage* backgroundImage;
	int mouseX, mouseY;
	AppList lastApps;
	IPropertyWatch[] propertyWatchers;

	this(XBackend x, bool vertical, int width, PanelConfiguration config)
	{
		this.x = x;
		winWidth = width;
		winHeight = this.height = config.height;
		this.config = config;
		widgets = WidgetManager(vertical, width, config);
		int s = height.iconSizeForHeight;
		defaultAppIcon = read_image("res/icon/application.png").premultiply.scaleImage(s, s);
		background.w = width;
		background.h = height;
		background.c = ColFmt.RGBA;
		background.pixels = new ubyte[width * height * 4];
		version (BigEndian)
			(cast(uint[]) background.pixels)[] = 0x000000B0;
		else
			(cast(uint[]) background.pixels)[] = 0xB0000000;
		backgroundImage = XCreateImage(x.display, x.visual, 32, ZPixmap, 0,
				cast(char*) background.pixels.ptr, width, height, 32, 0);
	}

	void redraw(int xx, int y, int width, int height)
	{
		foreach (ref widget; widgets)
			if (widget.contains(xx, y, width, height))
				widget.queueRedraw();
		XPutImage(x.display, window, gc, backgroundImage, xx, y, xx, y, width, height);
	}

	void mouseMove(int x, int y)
	{
		auto oldX = mouseX;
		mouseX = x;
		mouseY = y;
		foreach (ref widget; widgets)
		{
			if ((widget.isHovered(x, config.widgetBaselineMargin)
					|| widget.isHovered(oldX, config.widgetBaselineMargin)) && widget.hasHover)
				widget.queueRedraw();
			if (cast(IMouseWatch) widget.widget && widget.isHovered(x, config.widgetBaselineMargin))
				(cast(IMouseWatch) widget.widget).mouseMove(widgets.vertical, x - widget.x, y - widget.y);
		}
	}

	void unhover()
	{
		mouseX = -1;
		mouseY = -1;
	}

	void mouseDown(int x, int y, int button)
	{
		foreach (ref widget; widgets)
			if (cast(IMouseWatch) widget.widget && widget.isHovered(x, config.widgetBaselineMargin))
			{
				(cast(IMouseWatch) widget.widget).mouseDown(widgets.vertical,
						x - widget.x, y - widget.y, button);
				return;
			}
		if (x > config.barBaselinePadding && x <= lastApps.length * (
				height.iconSizeForHeight + config.appIconPadding * 2 + config.appBaselineMargin))
		{
			// User clicked a running app, did you really expect something to happen?
		}
	}

	void mouseUp(int x, int y, int button)
	{
		foreach (ref widget; widgets)
			if (cast(IMouseWatch) widget.widget && widget.isHovered(x, config.widgetBaselineMargin))
			{
				(cast(IMouseWatch) widget.widget).mouseUp(widgets.vertical,
						x - widget.x, y - widget.y, button);
				return;
			}
	}

	void updateApps()
	{
		if (!config.enableAppList)
			return;
		apps.updateClientList(config.iconSize);
		apps.updateActive();
	}

	void updateActive()
	{
		if (!config.enableAppList)
			return;
		apps.updateActive();
		updateWindows();
	}

	void updateClientList()
	{
		if (!config.enableAppList)
			return;
		apps.updateClientList(config.iconSize);
		updateWindows();
	}

	void updateWindow(Window window)
	{
		if (!config.enableAppList)
			return;
		apps.updateWindow(window, config.iconSize);
		updateWindows();
	}

	void updateIcon(Window window)
	{
		if (!config.enableAppList)
			return;
		apps.updateIcon(window, config.iconSize);
		updateWindows();
	}

	void updateWindows()
	{
		auto s = height.iconSizeForHeight;
		background.fillRect!4(config.barBaselinePadding, 0,
				cast(int) lastApps.length * (s + config.appIconPadding * 2 + config.appBaselineMargin),
				height, [0, 0, 0, 0xB0]);
		int pos = config.barBaselinePadding + config.appBaselineMargin / 2;
		foreach (ref app; apps)
		{
			int y = (height - config.focusStripeHeight - s) / 2;
			bool active = apps.activeWindow == app.window;
			if (app.icon.w && app.icon.h && app.icon.c
					&& app.icon.pixels.length == app.icon.w * app.icon.h * app.icon.c)
				background.draw(app.icon, pos + config.appIconPadding, y, s, 0, active ? 255 : 200);
			else
				background.draw(defaultAppIcon, pos + config.appIconPadding, y, s, 0, active ? 200 : 128);
			if (active)
				background.fillRect!4(pos, height - config.focusStripeHeight,
						s + config.appIconPadding * 2, config.focusStripeHeight, [0xFF, 0x98, 0, 0xFF]);
			pos += s + config.appIconPadding * 2 + config.appBaselineMargin;
		}
		XPutImage(x.display, window, gc, backgroundImage, config.barBaselinePadding,
				0, config.barBaselinePadding, 0, cast(int) max(lastApps.length,
					apps.length) * (s + config.appIconPadding * 2 + config.appBaselineMargin), height);
		lastApps = apps;
	}

	void update(Bar bar)
	{
		bool updateAll;
		int toClear;
		int lastX;
		foreach (ref widget; widgets)
		{
			widget.update(bar);
			if (widget.requiresRedraw() || updateAll)
			{
				auto newW = widget.widget.width(widgets.vertical);
				if (newW != widget.w)
				{
					updateAll = true;
					toClear += widget.w - newW;
					widget.w = newW;
					widgets.regen();
				}
				else if (updateAll)
					widgets.regen();
				widget.h = widget.widget.height(widgets.vertical);
				bool hovered = widget.isHovered(mouseX, config.widgetBaselineMargin);
				auto texture = widget.redraw(widgets.vertical, bar, hovered);
				assert(texture.w <= widget.w && texture.h <= widget.h);
				if (widget.hasHover)
				{
					background.fillRect!4(widget.x - config.widgetBaselineMargin / 2, 0,
							widget.w + config.widgetBaselineMargin, height, hovered ? [0x20,
							0x20, 0x20, 0xB0] : [0, 0, 0, 0xB0]);
				}
				else
					background.fillRect!4(widget.x, widget.y, widget.w, widget.h, [0, 0, 0, 0xB0]);
				background.draw(texture, widget.x, widget.y);
				XPutImage(x.display, window, gc, backgroundImage,
						widget.x - config.widgetBaselineMargin / 2, 0, widget.x - config.widgetBaselineMargin / 2,
						0, widget.w + config.widgetBaselineMargin, height);
				lastX = widget.x;
				widget.clearRedraw();
			}
		}
		if (toClear > 0)
		{
			background.fillRect!4(lastX - toClear, 0, toClear, height, [0, 0, 0, 0xB0]);
			XPutImage(x.display, window, gc, backgroundImage, lastX - toClear, 0,
					lastX - toClear, 0, toClear, height);
		}
	}

	void setup()
	{
		XStoreName(x.display, window, panelName);
		XSetIconName(x.display, window, panelName);

		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_NAME],
				XAtom[AtomName.UTF8_STRING], 8, PropModeReplace,
				cast(ubyte*) panelName, dPanelName.length);

		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_ICON_NAME],
				XAtom[AtomName.UTF8_STRING], 8, PropModeReplace,
				cast(ubyte*) panelName, dPanelName.length);

		long val = cast(long) XAtom[AtomName._NET_WM_WINDOW_TYPE_DOCK];
		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_WINDOW_TYPE],
				XA_ATOM, 32, PropModeReplace, cast(ubyte*)&val, 1);

		val = 0xFFFFFFFF; // All desktops
		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_DESKTOP],
				XA_CARDINAL, 32, PropModeReplace, cast(ubyte*)&val, 1);

		Atom[] state;
		state ~= XAtom[AtomName._NET_WM_STATE_STICKY];
		state ~= XAtom[AtomName._NET_WM_STATE_SKIP_TASKBAR];
		state ~= XAtom[AtomName._NET_WM_STATE_SKIP_PAGER];
		state ~= XAtom[AtomName._NET_WM_STATE_ABOVE];
		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_STATE], XA_ATOM,
				32, PropModeReplace, cast(ubyte*) state.ptr, cast(int) state.length);

		long[5] undecorated = [2, 0, 0, 0, 0];
		XChangeProperty(x.display, window, XAtom[AtomName._MOTIF_WM_HINTS],
				XAtom[AtomName._MOTIF_WM_HINTS], 32, PropModeReplace, cast(ubyte*) undecorated.ptr, 5);

		Atom ver = 5;
		XChangeProperty(x.display, window, XAtom[AtomName.XdndAware], XA_ATOM, 32,
				PropModeReplace, cast(ubyte*)&ver, 1);

		Atom yes = 1;
		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_HANDLED_ICONS],
				XA_ATOM, 32, PropModeReplace, cast(ubyte*)&yes, 1);

		XSelectInput(x.display, window, ExposureMask | EnterWindowMask | LeaveWindowMask
				| ButtonPressMask | ButtonReleaseMask | KeyPressMask | PointerMotionMask);
		XSetWMProtocols(x.display, window, [XAtom[AtomName.WM_DELETE_WINDOW],
				XAtom[AtomName._NET_WM_PING]].ptr, 2);

		XSetWindowBackground(x.display, window, 0);

		setupStrut();
	}

	void setupStrut()
	{
		long[12] strut = 0;
		if (dock == Dock.Left)
		{
			strut[0] = winWidth;
			strut[4] = winY;
			strut[5] = winY + winHeight;
		}
		if (dock == Dock.Right)
		{
			strut[1] = winWidth;
			strut[6] = winY;
			strut[7] = winY + winHeight;
		}
		if (dock == Dock.Top)
		{
			strut[2] = winHeight;
			strut[8] = winX;
			strut[9] = winX + winWidth;
		}
		if (dock == Dock.Bottom)
		{
			strut[3] = winHeight;
			strut[10] = winX;
			strut[11] = winX + winWidth;
		}
		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_STRUT],
				XA_CARDINAL, 32, PropModeReplace, cast(ubyte*) strut.ptr, 4);
		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_STRUT_PARTIAL],
				XA_CARDINAL, 32, PropModeReplace, cast(ubyte*) strut.ptr, 12);
	}

	ref Panel add(Widget widget)
	{
		if (cast(IPropertyWatch) widget)
			propertyWatchers ~= cast(IPropertyWatch) widget;
		widgets.add(widget);
		return this;
	}
}

struct FontFamily
{
	union
	{
		FT_Face[4] fonts;
		struct
		{
			FT_Face primary, secondary, neutral, fallback;
		}
	}
}

struct Bar
{
	BarConfiguration config;
	FT_Library ft;
	FontFamily fontFamily;

	XBackend x;
	IWindowManager[Window] widgetWindows;

	Panel[] panels;
	int trayIndex = -1;

	void ownWindow(Window window, IWindowManager mgr)
	{
		widgetWindows[window] = mgr;
	}

	ref Panel addPanel(Screen screen, Dock dock, PanelConfiguration config = PanelConfiguration.init)
	{
		Panel panel = Panel(x, false, x.screens[screen].width, config);
		panel.index = cast(int) panels.length;
		panel.screen = screen;
		panel.dock = dock;
		panel.winX = x.screens[screen].x;
		panel.winY = x.screens[screen].y + x.screens[screen].height - config.height;

		XSetWindowAttributes attr;
		attr.colormap = XCreateColormap(x.display, x.rootWindow, x.visual, AllocNone);
		attr.border_pixel = 0;
		attr.background_pixel = 0;
		ulong mask = CWEventMask | CWColormap | CWBackPixel | CWBorderPixel;
		panel.window = XCreateWindow(x.display, x.rootWindow, panel.winX,
				panel.winY, panel.winWidth, panel.winHeight, 0, x.vinfo.depth,
				InputOutput, x.visual, mask, &attr);

		XClassHint classHint;
		classHint.res_class = cast(char*) "dwin-bar".ptr;
		classHint.res_name = cast(char*) "dwin-bar-panel".ptr;
		XSetClassHint(x.display, panel.window, &classHint);

		panel.gc = XCreateGC(x.display, panel.window, 0, null);

		panel.setup();

		panels ~= panel;
		return panels[$ - 1];
	}

	void tray(Panel panel) @property
	{
		trayIndex = panel.index;
	}

	Panel tray() @property
	{
		if (trayIndex < 0)
			return Panel.init;
		return panels[trayIndex];
	}

	void start()
	{
		bool enableTray;
		//if (trayIndex != -1)
		//{
		//	SysTray.instance.start(x, panels[trayIndex]);
		//	enableTray = true;
		//}

		foreach (ref panel; panels)
			panel.updateApps();

		XSetWindowAttributes attrib;
		attrib.event_mask = PropertyChangeMask;
		XChangeWindowAttributes(x.display, x.rootWindow, CWEventMask, &attrib);

		foreach (ref panel; panels)
		{
			XMapWindow(x.display, panel.window);
			panel.redraw(0, 0, panel.winWidth, panel.winHeight);
		}

		bool running = true;
		XEvent e;
		while (running)
		{
			while (XPending(x.display) > 0)
			{
				XNextEvent(x.display, &e);
				if (e.type == ClientMessage)
				{
					if (e.xclient.message_type == XAtom[AtomName.WM_PROTOCOLS])
					{
						const atom = cast(Atom) e.xclient.data.l[0];
						if (atom == XAtom[AtomName.WM_DELETE_WINDOW])
						{
							foreach (ref panel; panels)
								if (panel.window == e.xclient.window)
									running = false;
							auto ptr = e.xclient.window in widgetWindows;
							if (ptr)
								(*ptr).windowClose(e.xclient.window);
						}
						else if (atom == XAtom[AtomName._NET_WM_PING])
							XSendEvent(x.display, x.root, false,
									SubstructureNotifyMask | SubstructureRedirectMask, &e);
						else
							std.stdio.writeln("Unhandled WM_PROTOCOLS Atom: ", atom);
					}
					//if (enableTray && e.xclient.message_type == XAtom[AtomName._NET_SYSTEM_TRAY_OPCODE]
					//		&& e.xclient.window == SysTray.instance.handle)
					//	SysTray.instance.handleEvent(e.xclient);
				}
				else if (e.type == Expose)
				{
					if (e.xexpose.count == 0)
					{
						foreach (ref panel; panels)
							if (e.xexpose.window == panel.window)
							{
								panel.redraw(e.xexpose.x, e.xexpose.y, e.xexpose.width, e.xexpose.height);
								break;
							}
						auto ptr = e.xexpose.window in widgetWindows;
						if (ptr)
							(*ptr).windowExpose(e.xexpose.window, e.xexpose.x, e.xexpose.y,
									e.xexpose.width, e.xexpose.height);
					}
				}
				else if (e.type == MotionNotify)
				{
					foreach (ref panel; panels)
						if (e.xmotion.window == panel.window)
						{
							panel.mouseMove(e.xmotion.x, e.xmotion.y);
							break;
						}
					auto ptr = e.xmotion.window in widgetWindows;
					if (ptr)
						(*ptr).windowMouseMove(e.xmotion.window, e.xmotion.x, e.xmotion.y);
				}
				else if (e.type == EnterNotify)
				{
					foreach (ref panel; panels)
						if (e.xcrossing.window == panel.window)
						{
							panel.mouseMove(e.xcrossing.x, e.xcrossing.y);
							break;
						}
					auto ptr = e.xcrossing.window in widgetWindows;
					if (ptr)
						(*ptr).windowMouseMove(e.xcrossing.window, e.xcrossing.x, e.xcrossing.y);
				}
				else if (e.type == LeaveNotify)
				{
					foreach (ref panel; panels)
						if (e.xcrossing.window == panel.window)
						{
							panel.unhover();
							break;
						}
					auto ptr = e.xcrossing.window in widgetWindows;
					if (ptr)
						(*ptr).windowMouseMove(e.xcrossing.window, e.xcrossing.x, e.xcrossing.y);
				}
				else if (e.type == ButtonPress)
				{
					foreach (ref panel; panels)
						if (e.xbutton.window == panel.window)
						{
							panel.mouseDown(e.xbutton.x, e.xbutton.y, e.xbutton.button);
							break;
						}
					auto ptr = e.xbutton.window in widgetWindows;
					if (ptr)
						(*ptr).windowMouseDown(e.xbutton.window, e.xbutton.x, e.xbutton.y, e.xbutton.button);
				}
				else if (e.type == ButtonRelease)
				{
					foreach (ref panel; panels)
						if (e.xbutton.window == panel.window)
						{
							panel.mouseUp(e.xbutton.x, e.xbutton.y, e.xbutton.button);
							break;
						}
					auto ptr = e.xbutton.window in widgetWindows;
					if (ptr)
						(*ptr).windowMouseUp(e.xbutton.window, e.xbutton.x, e.xbutton.y, e.xbutton.button);
				}
				else if (e.type == PropertyNotify)
				{
					foreach (ref panel; panels)
						foreach (ref watch; panel.propertyWatchers)
							watch.onPropertyChange(e.xproperty.window, e.xproperty.atom);
					if (e.xproperty.window == x.rootWindow)
					{
						if (e.xproperty.atom == XAtom[AtomName._NET_ACTIVE_WINDOW])
						{
							foreach (ref panel; panels)
								panel.updateActive();
						}
						else if (e.xproperty.atom == XAtom[AtomName._NET_CURRENT_DESKTOP])
						{
						}
						else if (e.xproperty.atom == XAtom[AtomName._NET_CLIENT_LIST])
						{
							foreach (ref panel; panels)
								panel.updateClientList();
						}
						else if (e.xproperty.atom == XAtom[AtomName._NET_CLIENT_LIST_STACKING])
						{
						}
						else
							std.stdio.writeln("Unknown Property changed: ",
									XGetAtomName(x.display, e.xproperty.atom).fromStringz);
					}
					else
					{
						if (e.xproperty.atom == XAtom[AtomName._NET_WM_USER_TIME]
								|| e.xproperty.atom == XAtom[AtomName._NET_WM_ICON_NAME]
								|| e.xproperty.atom == XAtom[AtomName.WM_ICON_NAME]
								|| e.xproperty.atom == XAtom[AtomName._NET_WM_OPAQUE_REGION])
						{
						}
						else if (e.xproperty.atom == XAtom[AtomName._NET_WM_NAME]
								|| e.xproperty.atom == XAtom[AtomName.WM_NAME]
								|| e.xproperty.atom == XAtom[AtomName.WM_STATE]
								|| e.xproperty.atom == XAtom[AtomName._NET_WM_STATE]
								|| e.xproperty.atom == XAtom[AtomName.WM_HINTS])
						{
							foreach (ref panel; panels)
								panel.updateWindow(e.xproperty.window);
						}
						else if (e.xproperty.atom == XAtom[AtomName._NET_WM_ICON])
						{
							foreach (ref panel; panels)
								panel.updateIcon(e.xproperty.window);
						}
						else
							std.stdio.writeln("For window ", getWindowTitle(x, e.xproperty.window),
									" unknown Property changed: ", XGetAtomName(x.display,
										e.xproperty.atom).fromStringz);
						/* Window in bar changed (title, minimized, etc) */
					}
				}
				/*else if (e.type == DestroyNotify && enableTray)
					SysTray.instance.handleRemove(e.xdestroywindow.window);
				else if (e.type == UnmapNotify && enableTray)
					SysTray.instance.handleRemove(e.xunmap.window);*/
				else
					debug std.stdio.writeln("Unhandled event: ", e.type);
			}
			foreach (ref panel; panels)
				panel.update(this);
			Thread.sleep(20.msecs);
		}
	}
}

enum FTErrors
{
	FT_Err_Ok = 0x00,
	FT_Err_Cannot_Open_Resource = 0x01,
	FT_Err_Unknown_File_Format = 0x02,
	FT_Err_Invalid_File_Format = 0x03,
	FT_Err_Invalid_Version = 0x04,
	FT_Err_Lower_Module_Version = 0x05,
	FT_Err_Invalid_Argument = 0x06,
	FT_Err_Unimplemented_Feature = 0x07,
	FT_Err_Invalid_Table = 0x08,
	FT_Err_Invalid_Offset = 0x09,
	FT_Err_Array_Too_Large = 0x0A,
	FT_Err_Missing_Module = 0x0B,
	FT_Err_Missing_Property = 0x0C,

	FT_Err_Invalid_Glyph_Index = 0x10,
	FT_Err_Invalid_Character_Code = 0x11,
	FT_Err_Invalid_Glyph_Format = 0x12,
	FT_Err_Cannot_Render_Glyph = 0x13,
	FT_Err_Invalid_Outline = 0x14,
	FT_Err_Invalid_Composite = 0x15,
	FT_Err_Too_Many_Hints = 0x16,
	FT_Err_Invalid_Pixel_Size = 0x17,

	FT_Err_Invalid_Handle = 0x20,
	FT_Err_Invalid_Library_Handle = 0x21,
	FT_Err_Invalid_Driver_Handle = 0x22,
	FT_Err_Invalid_Face_Handle = 0x23,
	FT_Err_Invalid_Size_Handle = 0x24,
	FT_Err_Invalid_Slot_Handle = 0x25,
	FT_Err_Invalid_CharMap_Handle = 0x26,
	FT_Err_Invalid_Cache_Handle = 0x27,
	FT_Err_Invalid_Stream_Handle = 0x28,

	FT_Err_Too_Many_Drivers = 0x30,
	FT_Err_Too_Many_Extensions = 0x31,

	FT_Err_Out_Of_Memory = 0x40,
	FT_Err_Unlisted_Object = 0x41,

	FT_Err_Cannot_Open_Stream = 0x51,
	FT_Err_Invalid_Stream_Seek = 0x52,
	FT_Err_Invalid_Stream_Skip = 0x53,
	FT_Err_Invalid_Stream_Read = 0x54,
	FT_Err_Invalid_Stream_Operation = 0x55,
	FT_Err_Invalid_Frame_Operation = 0x56,
	FT_Err_Nested_Frame_Access = 0x57,
	FT_Err_Invalid_Frame_Read = 0x58,

	FT_Err_Raster_Uninitialized = 0x60,
	FT_Err_Raster_Corrupted = 0x61,
	FT_Err_Raster_Overflow = 0x62,
	FT_Err_Raster_Negative_Height = 0x63,

	FT_Err_Too_Many_Caches = 0x70,

	FT_Err_Invalid_Opcode = 0x80,
	FT_Err_Too_Few_Arguments = 0x81,
	FT_Err_Stack_Overflow = 0x82,
	FT_Err_Code_Overflow = 0x83,
	FT_Err_Bad_Argument = 0x84,
	FT_Err_Divide_By_Zero = 0x85,
	FT_Err_Invalid_Reference = 0x86,
	FT_Err_Debug_OpCode = 0x87,
	FT_Err_ENDF_In_Exec_Stream = 0x88,
	FT_Err_Nested_DEFS = 0x89,
	FT_Err_Invalid_CodeRange = 0x8A,
	FT_Err_Execution_Too_Long = 0x8B,
	FT_Err_Too_Many_Function_Defs = 0x8C,
	FT_Err_Too_Many_Instruction_Defs = 0x8D,
	FT_Err_Table_Missing = 0x8E,
	FT_Err_Horiz_Header_Missing = 0x8F,
	FT_Err_Locations_Missing = 0x90,
	FT_Err_Name_Table_Missing = 0x91,
	FT_Err_CMap_Table_Missing = 0x92,
	FT_Err_Hmtx_Table_Missing = 0x93,
	FT_Err_Post_Table_Missing = 0x94,
	FT_Err_Invalid_Horiz_Metrics = 0x95,
	FT_Err_Invalid_CharMap_Format = 0x96,
	FT_Err_Invalid_PPem = 0x97,
	FT_Err_Invalid_Vert_Metrics = 0x98,
	FT_Err_Could_Not_Find_Context = 0x99,
	FT_Err_Invalid_Post_Table_Format = 0x9A,
	FT_Err_Invalid_Post_Table = 0x9B,

	FT_Err_Syntax_Error = 0xA0,
	FT_Err_Stack_Underflow = 0xA1,
	FT_Err_Ignore = 0xA2,
	FT_Err_No_Unicode_Glyph_Name = 0xA3,
	FT_Err_Glyph_Too_Big = 0xA4,

	FT_Err_Missing_Startfont_Field = 0xB0,
	FT_Err_Missing_Font_Field = 0xB1,
	FT_Err_Missing_Size_Field = 0xB2,
	FT_Err_Missing_Fontboundingbox_Field = 0xB3,
	FT_Err_Missing_Chars_Field = 0xB4,
	FT_Err_Missing_Startchar_Field = 0xB5,
	FT_Err_Missing_Encoding_Field = 0xB6,
	FT_Err_Missing_Bbx_Field = 0xB7,
	FT_Err_Bbx_Too_Big = 0xB8,
	FT_Err_Corrupted_Font_Header = 0xB9,
	FT_Err_Corrupted_Font_Glyphs = 0xBA,

	FT_Err_Max,
}

void enforceFT(FT_Error err)
{
	if (err == 0)
		return;
	throw new Exception((cast(FTErrors) err).to!string);
}

void loadFace(FT_Library lib, string font, FT_Face* face)
{
	string absPath;
	if (font.canFind("/"))
		absPath = font;
	else
	{
		auto fontProc = execute(["fc-match", font]);
		if (fontProc.status != 0)
			throw new Exception("fc-match returned non-zero");
		auto idx = fontProc.output.indexOf(':');
		string fontFile = fontProc.output[0 .. idx];
		foreach (file; dirEntries("/usr/share/fonts", SpanMode.depth))
			if (file.baseName == fontFile)
				absPath = file;
		if ("~/.local/share/fonts".expandTilde.exists)
			foreach (file; dirEntries("~/.local/share/fonts".expandTilde, SpanMode.depth))
				if (file.baseName == fontFile)
					absPath = file;
	}
	import std.stdio;

	writeln("Loading font from ", absPath);
	enforceFT(FT_New_Face(lib, absPath.toStringz, 0, face));
	enforceFT(FT_Set_Char_Size(*face, 0, 16 * 64 + 32, 0, 0));
	enforceFT(FT_Select_Charmap(*face, FT_ENCODING_UNICODE));
}

Bar loadBar(BarConfiguration config = BarConfiguration.init)
{
	DerelictFT.load();

	Bar bar;
	bar.x = new XBackend(config.displayName);
	bar.config = config;

	enforceFT(FT_Init_FreeType(&bar.ft));
	loadFace(bar.ft, config.fontFallback, &bar.fontFamily.fallback);
	loadFace(bar.ft, config.fontPrimary, &bar.fontFamily.primary);
	loadFace(bar.ft, config.fontSecondary, &bar.fontFamily.secondary);
	loadFace(bar.ft, config.fontNeutral, &bar.fontFamily.neutral);

	return bar;
}
