module dwinbar.panels;

import x11.Xlib;
import x11.X;

import dwinbar.backend.panel;
import dwinbar.backend.xbackend;

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
		foreach (panel; _panels)
			foreach (widget; _widgets)
				panel.addWidget(widget);

		foreach (panel; _panels)
			panel.sortWidgets();

		bool running = true;
		XEvent e;

		while (running)
		{
			while (XPending(_backend.display) > 0)
			{
				XNextEvent(_backend.display, &e);
				if (e.type == ClientMessage)
				{
					if (e.xclient.message_type == XAtom[AtomName.WM_PROTOCOLS]
							&& cast(Atom) e.xclient.data.l[0] == XAtom[AtomName.WM_DELETE_WINDOW])
						running = false;
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

private:
	XBackend _backend;
	Panel[] _panels;
	Widget[] _widgets;
}
