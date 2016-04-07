module dwinbar.panels;

import x11.Xlib;
import x11.X;

import dwinbar.backend.panel;
import dwinbar.backend.xbackend;
import dwinbar.backend.systray;

import dwinbar.widgets.widget;

import core.thread;

class Panels
{
	this(XBackend backend)
	{
		_backend = backend;
	}

	void start()
	{
		bool enableTaskBar = false;

		if (_trayHolder !is null)
		{
			SysTray.instance.start(_backend, _trayHolder);
			enableTaskBar = true;
		}

		foreach (panel; _panels)
			foreach (widget; _widgets)
				panel.addWidget(widget);

		foreach (panel; _panels)
			panel.sortWidgets();

		running = true;
		XEvent e;

		while (running)
		{
			while (XPending(_backend.display) > 0)
			{
				XNextEvent(_backend.display, &e);
				if (e.type == ClientMessage)
				{
					if (e.xclient.message_type == XAtom[AtomName.WM_PROTOCOLS])
					{
						const atom = cast(Atom) e.xclient.data.l[0];
						if (atom == XAtom[AtomName.WM_DELETE_WINDOW])
							running = false;
						else if (atom == XAtom[AtomName._NET_WM_PING])
						{
							XSendEvent(_backend.display, _backend.root, false,
								SubstructureNotifyMask | SubstructureRedirectMask,
								&e);
						}
						else
							std.stdio.writeln("Unhandled WM_PROTOCOLS Atom: ", atom);
					}
					if (enableTaskBar
							&& e.xclient.message_type == XAtom[AtomName._NET_SYSTEM_TRAY_OPCODE]
							&& e.xclient.window == SysTray.instance.handle)
					{
						SysTray.instance.handleEvent(e.xclient);
					}
				}
				else if (e.type == Expose)
				{ /* Ignore */ }
				else if (e.type == DestroyNotify)
				{
					if (enableTaskBar)
					{
						SysTray.instance.handleRemove(e.xdestroywindow.window);
					}
					else
					{
						std.stdio.writeln(e.xdestroywindow.window, " got destroyed randomly!");
					}
				}
				else if (e.type == UnmapNotify)
				{
					if (enableTaskBar)
					{
						SysTray.instance.handleRemove(e.xunmap.window);
					}
					else
					{
						std.stdio.writeln(e.xunmap.window, " got unmapped randomly!");
					}
				}
				else
				{
					debug std.stdio.writeln("Unhandled event: ", e.type);
				}

				foreach (panel; _panels)
					if (e.xany.window == panel.window)
						panel.handleEvent(e);
			}

			foreach (panel; _panels)
				panel.paint();

			Thread.sleep(10.msecs);
		}
	}

	Panel addPanel(PanelInfo info)
	{
		auto panel = new Panel(_backend, info);
		_panels ~= panel;
		return panel;
	}

	void addGlobalWidget(Widget[] widgets...)
	{
		_widgets ~= widgets;
	}

	auto taskBar() @property
	{
		return _trayHolder;
	}

	void taskBar(Panel value) @property
	{
		if (running)
			throw new Exception("Can't enable task bar while bar is running");
		_trayHolder = value;
	}

private:
	bool running = false;
	Panel _trayHolder = null;
	XBackend _backend;
	Panel[] _panels;
	Widget[] _widgets;
}
