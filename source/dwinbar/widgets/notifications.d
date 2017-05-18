module dwinbar.widgets.notifications;

import dwinbar.backend.xbackend;
import dwinbar.backend.icongen;
import dwinbar.widget;
import dwinbar.bar;

import derelict.freetype.ft;

import ddbus;
import ddbus.c_lib;

import std.algorithm;
import std.array;
import std.stdio;
import std.typecons;
import std.exception;
import std.datetime;

import tinyevent;

enum dNotifyName = "dwin-bar notification";
char* notifyName = cast(char*)(dNotifyName ~ '\0').ptr;

enum MaxNotificationsPixels = 400;

struct Notification
{
	uint id;
	string app;
	string icon;
	string title, content;
	string[] actions;
	int timeout;
	bool visible, deffered;
	int y, arrowX;

	Window window;
	GC gc;
	IFImage bg;
	XImage* bgImg;

	int notificationWidth = 400;
	int notificationHeight = 96;

	void updatePosition(XBackend x)
	{
		bool nowDeffered = y > MaxNotificationsPixels;
		if (deffered && !nowDeffered)
			XMapWindow(x.display, window);
		deffered = nowDeffered;
		if (!deffered && visible)
		{
			XMoveWindow(x.display, window, x.screens[0].width - notificationWidth - 16,
					x.screens[0].height - notificationHeight - 16 - 32 - y);
		}
	}

	void open(ref Bar bar, int y)
	{
		auto x = bar.x;
		auto font = bar.fontFamily;

		this.y = y;
		enforceFT(FT_Set_Char_Size(font.neutral, 0, 11 * 64 + 32, 0, 0));
		enforceFT(FT_Set_Char_Size(font.fallback, 0, 11 * 64 + 32, 0, 0));
		auto text = TextLayout.layout(content, notificationWidth - 64 - 32 - 16, 300, 16, font, 2);
		int modHeight = cast(int)(text.height + 68);
		if (modHeight > notificationHeight)
			notificationHeight = modHeight;

		IFImage appIcon;
		if (icon)
		{
			writeln(icon);
		}
		//else
		appIcon = read_image("res/icon/message.png", 4).premultiplyReverse;

		XSetWindowAttributes attr;
		attr.colormap = XCreateColormap(x.display, x.rootWindow, x.visual, AllocNone);
		attr.border_pixel = 0;
		attr.background_pixel = 0;
		ulong mask = CWEventMask | CWColormap | CWBackPixel | CWBorderPixel;
		window = XCreateWindow(x.display, x.rootWindow, 0, 0, notificationWidth,
				notificationHeight, 0, x.vinfo.depth, InputOutput, x.visual, mask, &attr);
		gc = XCreateGC(x.display, window, 0, null);

		XWMHints hints;
		hints.flags = InputHint | StateHint | WindowGroupHint;
		hints.input = false;
		hints.nitial_state = NormalState;
		hints.window_group = bar.panels[0].window;
		XSetWMHints(x.display, window, &hints);

		XSizeHints sizeHints;
		sizeHints.x = sizeHints.y = 0;
		sizeHints.min_width = sizeHints.max_width = notificationWidth;
		sizeHints.min_height = sizeHints.max_height = notificationHeight;
		sizeHints.base_width = sizeHints.base_height = 0;
		sizeHints.win_gravity = 1;
		sizeHints.flags = PPosition | PMinSize | PMaxSize | PBaseSize | PWinGravity;
		XSetWMNormalHints(x.display, window, &sizeHints);

		XStoreName(x.display, window, notifyName);
		XSetIconName(x.display, window, notifyName);
		XClassHint classHint;
		classHint.res_class = cast(char*) "dwin-bar".ptr;
		classHint.res_name = cast(char*) "dwin-bar-notification".ptr;
		XSetClassHint(x.display, window, &classHint);

		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_NAME],
				XAtom[AtomName.UTF8_STRING], 8, PropModeReplace,
				cast(ubyte*) notifyName, dNotifyName.length);

		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_ICON_NAME],
				XAtom[AtomName.UTF8_STRING], 8, PropModeReplace,
				cast(ubyte*) notifyName, dNotifyName.length);

		long val = 0;
		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_DESKTOP],
				XA_CARDINAL, 32, PropModeReplace, cast(ubyte*)&val, 1);

		val = cast(long) XAtom[AtomName._NET_WM_WINDOW_TYPE_NOTIFICATION];
		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_WINDOW_TYPE],
				XA_ATOM, 32, PropModeReplace, cast(ubyte*)&val, 1);

		val = bar.panels[0].window;
		XChangeProperty(x.display, window, XAtom[AtomName.WM_CLIENT_LEADER],
				XA_WINDOW, 32, PropModeReplace, cast(ubyte*)&val, 1);

		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_OPAQUE_REGION],
				XA_CARDINAL, 32, PropModeReplace, cast(ubyte*)&val, 0);

		Atom[] state;
		state ~= XAtom[AtomName._NET_WM_STATE_ABOVE];
		state ~= XAtom[AtomName._NET_WM_STATE_STICKY];
		state ~= XAtom[AtomName._NET_WM_STATE_SKIP_TASKBAR];
		state ~= XAtom[AtomName._NET_WM_STATE_SKIP_PAGER];
		XChangeProperty(x.display, window, XAtom[AtomName._NET_WM_STATE], XA_ATOM,
				32, PropModeReplace, cast(ubyte*) state.ptr, cast(int) state.length);

		long[5] undecorated = [2, 0, 0, 0, 0];
		XChangeProperty(x.display, window, XAtom[AtomName._MOTIF_WM_HINTS],
				XAtom[AtomName._MOTIF_WM_HINTS], 32, PropModeReplace, cast(ubyte*) undecorated.ptr, 5);

		Atom ver = 5;
		XChangeProperty(x.display, window, XAtom[AtomName.XdndAware], XA_ATOM, 32,
				PropModeReplace, cast(ubyte*)&ver, 1);

		XSelectInput(x.display, window, ExposureMask | ButtonPressMask);

		XSetWMProtocols(x.display, window, [XAtom[AtomName.WM_DELETE_WINDOW],
				XAtom[AtomName._NET_WM_PING]].ptr, 2);

		XSetWindowBackground(x.display, window, 0);

		if (y > MaxNotificationsPixels)
			deffered = true;
		else
			XMapWindow(x.display, window);
		bg.w = notificationWidth;
		bg.h = notificationHeight;
		bg.c = ColFmt.RGBA;
		bg.pixels = new ubyte[bg.w * bg.h * bg.c];
		for (int i = 0; i < bg.pixels.length; i += 4)
		{
			bg.pixels[i + 0] = 0xFE;
			bg.pixels[i + 1] = 0xFE;
			bg.pixels[i + 2] = 0xFE;
			bg.pixels[i + 3] = 0xFF;
		}
		float[2] pos;
		bg.draw(appIcon, 16, 18);
		pos = bg.drawText(font, 2, app, 34, 16 + 12, [0xFE, 0x5A, 0x3D, 0xFF]);
		pos = bg.drawText(font, 2, " · now", pos[0], 16 + 12, [0, 0, 0, 0x89]);
		if (actions.length)
		{
			arrowX = cast(int)(pos[0] + 4);
			bg.draw(read_image("res/icon/expand-more.png").premultiplyReverse, arrowX, 16, 0, 0, 0x80);
		}
		enforceFT(FT_Set_Char_Size(font.neutral, 0, 13 * 64, 0, 0));
		enforceFT(FT_Set_Char_Size(font.fallback, 0, 13 * 64, 0, 0));
		bg.drawText(font, 2, title, 16, 48, [0, 0, 0, 0xDD]);
		text.draw(bg, 16, 68, [0, 0, 0, 0x89]);
		enforceFT(FT_Set_Char_Size(font.neutral, 0, 16 * 64 + 32, 0, 0));
		enforceFT(FT_Set_Char_Size(font.fallback, 0, 16 * 64 + 32, 0, 0));
		bgImg = XCreateImage(x.display, x.visual, 32, ZPixmap, 0,
				cast(char*) bg.pixels.ptr, notificationWidth, notificationHeight, 32, 0);
	}

	void draw(XBackend x)
	{
		XPutImage(x.display, window, gc, bgImg, 0, 0, 0, 0, notificationWidth, notificationHeight);
	}

	void close(XBackend x)
	{
		visible = false;
		XUnmapWindow(x.display, window);
	}

	bool click(int mx, int my)
	{
		if (actions.length && mx >= arrowX && mx < arrowX + 16 && my >= 16 && my <= 32)
		{
			// TODO: expand
			return true;
		}
		return false;
	}

	void loadHints(Variant!DBusAny[string] hints)
	{
		auto imageData = "image-data" in hints;
		auto image_data = "image_data" in hints;
		auto icon_data = "icon_data" in hints;
		auto imagePath = "image-path" in hints;
		auto image_path = "image_path" in hints;
		if (imageData)
			loadImage(imageData.data);
		else if (image_data)
			loadImage(image_data.data);
		else if (icon_data)
			loadImage(icon_data.data);
		else if (imagePath)
			loadImagePath(imagePath.data);
		else if (image_path)
			loadImagePath(image_path.data);
	}

	void loadImage(DBusAny image)
	{
		import std.typecons;

		auto data = image.to!(Tuple!(int, "width", int, "height", int,
				"rowstride", bool, "hasAlpha", int, "bps", int, "channels", ubyte[], "pixels"));

		if (data.bps != 8)
			return;
		IFImage icon;
		icon.w = data.width;
		icon.h = data.height;
		icon.c = ColFmt.RGBA;
		if (data.channels == 4)
		{
			icon.pixels.length = icon.w * icon.h * icon.c;
			for (int y = 0; y < icon.h; y++)
				icon.pixels[y * icon.w * 4 .. y * icon.w * 4 + icon.w * 4] = data
					.pixels[y * data.rowstride .. y * data.rowstride + icon.w * 4];
		}
		else if (data.channels == 3)
		{
			icon.pixels.length = icon.w * icon.h * icon.c;
			for (int y = 0; y < icon.h; y++)
				for (int x = 0; x < icon.w; x++)
					icon.pixels[y * icon.w * 4 + x * 4 .. y * icon.w * 4 + x * 4 + 4] = data
						.pixels[y * data.rowstride + x * 3 .. y * data.rowstride + x * 3 + 3] ~ 0xFF;
		}
		else
			return;
		bg.draw(icon.scaleImage(64, 64).premultiplyReverse, notificationWidth - 64 - 16, 16);
	}

	void loadImagePath(DBusAny path)
	{

	}
}

class NotificationServer
{
	this(Bar* bar)
	{
		this.bar = bar;
	}

	string[] GetCapabilities()
	{
		return ["action-icons", "actions", "body", "body-hyperlinks", "body-images",
			"body-markup", "icon-multi", "icon-static", "persistence", "sound"];
	}

	uint Notify(string app_name, uint replaces_id, string app_icon, string summary,
			string body_, string[] actions, Variant!DBusAny[string] hints, int expire_timeout)
	{
		size_t idx = 0;
		if (replaces_id != 0)
		{
			foreach (i, n; all)
				if (n.id == replaces_id)
				{
					idx = i;
					break;
				}
			if (idx == 0)
			{
				idx = all.length;
				all ~= Notification(++index);
			}
		}
		else
		{
			idx = all.length;
			all ~= Notification(++index);
		}
		all[idx].app = app_name;
		all[idx].icon = app_icon;
		all[idx].title = summary;
		all[idx].content = body_;
		all[idx].actions = actions;
		all[idx].timeout = expire_timeout == -1 ? 10000 : expire_timeout;
		all[idx].visible = true;

		if (!all[idx].window)
		{
			all[idx].open(*bar, lastY);
			onWindowOpen.emit(all[idx].window);
		}
		all[idx].loadHints(hints);
		Restack();
		return all[idx].id;
	}

	void CloseNotification(uint id)
	{
		foreach (ref n; all)
			if (n.id == id)
			{
				n.close(bar.x);
				Restack();
				return;
			}
	}

	Tuple!(string, string, string, string) GetServerInformation()
	{
		typeof(return) ret;
		ret[0] = "dwin-bar"; // name
		ret[1] = "WebFreak"; // vendor
		ret[2] = "0.1.0"; // version
		ret[3] = "1.2"; // spec_version
		return ret;
	}

	void Restack()
	{
		lastY = 0;
		foreach (ref notification; all)
		{
			if (!notification.visible)
				continue;
			notification.y = lastY;
			notification.updatePosition(bar.x);
			lastY += notification.notificationHeight + 16;
		}
	}

	Event!Window onWindowOpen;

private:

	int lastY;
	Bar* bar;
	int index = 0;
	Notification[] all;
}

class NotificationsWidget : Widget, IWindowManager
{
	this(Bar* bar)
	{
		this.bar = bar;
		x = bar.x;
		notificationIcon = read_image("res/icon/bell-outline.png").premultiply;
		unreadNotificationIcon = read_image("res/icon/bell-ring.png").premultiply;
		conn = connectToBus();
		router = new MessageRouter();
		dbus = new NotificationServer(bar);
		dbus.onWindowOpen ~= &onWindowOpen;
		registerMethods(router, "/org/freedesktop/Notifications",
				"org.freedesktop.Notifications", dbus);
		std.stdio.writeln(router.callTable.byKey);
		registerRouter(conn, router);
		enforce(requestName(conn, "org.freedesktop.Notifications"));
	}

	override int width(bool) const
	{
		return 16;
	}

	override int height(bool) const
	{
		return 16;
	}

	override bool hasHover() @property
	{
		return true;
	}

	override IFImage redraw(bool vertical, Bar bar, bool hovered)
	{
		return dbus.all.length ? unreadNotificationIcon : notificationIcon;
	}

	override void update(Bar bar)
	{
		frameTimer.stop();
		int msecs = frameTimer.peek.to!("msecs", int);
		frameTimer.reset();
		frameTimer.start();
		if (!dbus_connection_read_write_dispatch(conn.conn, 0))
			throw new Exception("tick break");
		foreach (ref notification; dbus.all)
		{
			if (notification.visible && !notification.deffered && notification.timeout > 0)
			{
				notification.timeout -= msecs;
				if (notification.timeout <= 0)
				{
					notification.close(x);
					dbus.Restack();
				}
			}
		}
	}

	void onWindowOpen(Window window)
	{
		bar.ownWindow(window, this);
		queueRedraw();
	}

	void windowExpose(Window window, int, int, int, int)
	{
		foreach (ref notification; dbus.all)
		{
			if (notification.window == window)
			{
				if (notification.visible)
					notification.draw(x);
				return;
			}
		}
	}

	void windowClose(Window window)
	{
		foreach (ref notification; dbus.all)
		{
			if (notification.window == window)
			{
				notification.close(x);
				dbus.Restack();
				return;
			}
		}
	}

	void windowMouseDown(Window window, int mx, int my, int button)
	{
		foreach (ref notification; dbus.all)
		{
			if (notification.window == window)
			{
				if (button != 1 || !notification.click(mx, my))
					notification.close(x);
				dbus.Restack();
				return;
			}
		}
	}

	void windowMouseUp(Window window, int x, int y, int button)
	{
	}

	void windowMouseMove(Window window, int x, int y)
	{
	}

private:
	Bar* bar;
	XBackend x;
	StopWatch frameTimer;
	NotificationServer dbus;
	MessageRouter router;
	Connection conn;
	IFImage notificationIcon, unreadNotificationIcon;
}
