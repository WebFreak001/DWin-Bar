module dwinbar.widgets.mediaplayer;

import dwinbar.backend.dbus;
import dwinbar.widget;
import dwinbar.bar;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime.stopwatch;
import std.exception;
import std.file;
import std.math;
import std.path;
import std.range;
import std.stdio;
import std.typecons;
import std.uni;

import ddbus.exception;
import ddbus.util;

import tinyevent;

class ActiveMprisController
{
	BusName GetActiveBusName()
	{
		return busName(widget.activeName);
	}

	void Play()
	{
		widget.play();
	}

	void Pause()
	{
		widget.pause();
	}

	void PlayPause()
	{
		widget.playPause();
	}

	void Previous()
	{
		widget.previous();
	}

	void Next()
	{
		widget.next();
	}

private:
	MprisMediaPlayerWidget widget;
}

class MprisMediaPlayerWidget : Widget, IMouseWatch
{
	static immutable playerInterfaceName = interfaceName("org.mpris.MediaPlayer2.Player");
	static immutable mprisObjectPath = ObjectPath("/org/mpris/MediaPlayer2");

	this()
	{
		prepare();
	}

	this(FontFamily font)
	{
		this();

		this.font = font;
		sessionBus.attach();

		registerNames();

		prevIcon = read_image("res/icon/skip-previous.png").premultiply;
		pauseIcon = read_image("res/icon/pause.png").premultiply;
		playIcon = read_image("res/icon/play.png").premultiply;
		nextIcon = read_image("res/icon/skip-next.png").premultiply;
		updateClock.start();
	}

	private final void prepare()
	{
		activeController = new ActiveMprisController();
		activeController.widget = this;
	}

	override void loadBase(WidgetConfig config)
	{
		prepare();

		this.font = config.bar.fontFamily;
		sessionBus.attach();

		registerNames();

		prevIcon = read_image("res/icon/skip-previous.png").premultiply;
		pauseIcon = read_image("res/icon/pause.png").premultiply;
		playIcon = read_image("res/icon/play.png").premultiply;
		nextIcon = read_image("res/icon/skip-next.png").premultiply;
		updateClock.start();
	}

	override bool setProperty(string property, Json value)
	{
		switch (property)
		{
		default:
			return false;
		}
	}

	override int width(bool) const
	{
		if (!mpInterface || !playerInterface)
			return 0;
		return 24 * 3 + 8 + min(400, cast(int) ceil(measureText(cast() font, 1, label)[0]));
	}

	override int height(bool) const
	{
		return 32;
	}

	override bool hasHover() @property
	{
		return false;
	}

	override IFImage redraw(bool vertical, Bar bar, bool hovered)
	{
		if (!mpInterface || !playerInterface)
			return IFImage(0, 0, ColFmt.RGBA);
		IFImage canvas;
		canvas.w = width(vertical);
		canvas.h = height(vertical);
		canvas.c = ColFmt.RGBA;
		canvas.pixels.length = canvas.w * canvas.h * canvas.c;

		enum xOffset = (24 - 16) / 2;

		if (songLength != Duration.zero)
		{
			float progress = this.progress.peek.total!"usecs" / cast(float) songLength.total!"usecs";
			// stderr.writeln("Progress: ", progress);
			int width = cast(int)(canvas.w * progress);
			if (width >= 0 && width <= canvas.w)
			{
				if (width > 1)
					canvas.fillRect(1, canvas.h - 3, width - 1, 1, focusStripeColor);
				canvas.fillRect(0, canvas.h - 2, width, 2, focusStripeColor);
			}
		}

		canvas.draw(prevIcon, xOffset, 8, 0, 0, canPrev ? 255 : 90);
		canvas.draw(isPlaying ? pauseIcon : playIcon, 24 + xOffset, 8, 0, 0,
				(isPlaying ? canPause : canPlay) ? 255 : 90);
		canvas.draw(nextIcon, 24 * 2 + xOffset, 8, 0, 0, canNext ? 255 : 90);
		canvas.drawText(font, 1, label, 24 * 3 + 8, 14 + 8, cast(ubyte[4])[
				0xFF, 0xFF, 0xFF, 0xFF
				]);
		return canvas;
	}

	bool ensureConnection()
	{
		searchActivePlayer();
		return activeName.length && mpInterface && playerInterface;
	}

	void play()
	{
		if (!ensureConnection)
			return;
		playerInterface.Play();
		if (!progress.running)
			progress.start();
	}

	void pause()
	{
		if (!ensureConnection)
			return;
		playerInterface.Pause();
		if (progress.running)
			progress.stop();
	}

	void playPause()
	{
		if (!ensureConnection)
			return;
		playerInterface.PlayPause();
	}

	void previous()
	{
		if (!ensureConnection)
			return;
		playerInterface.Previous();
		progress.reset();
	}

	void next()
	{
		if (!ensureConnection)
			return;
		playerInterface.Next();
		progress.reset();
	}

	override void update(Bar)
	{
		if ((updateClock.peek <= 400.msecs && !force) || !ensureConnection)
			return;
		force = false;
		tick++;
		updateClock.reset();
		updateDBus();

		if (tick > 12 && isPlaying && spotify)
		{
			import dwinbar.webserver : getSpotifyCurrentlyPlaying;

			auto status = getSpotifyCurrentlyPlaying();
			if (!status.progress_ms.isNull)
				progress.setTimeElapsed(status.progress_ms.get.msecs);

			if (status.is_playing && !progress.running)
				progress.start();
			else if (!status.is_playing && progress.running)
				progress.stop();
			tick = 0;
		}
		else if (!isPlaying && progress.running)
			progress.stop();

		if (songLength != Duration.zero && isPlaying)
			queueRedraw();

		try
		{
			Variant!DBusAny[string] song;
			auto rawMeta = mpInterface.Get(playerInterfaceName, "Metadata");
			song = rawMeta.to!(Variant!DBusAny[string]);
			const newCanNext = mpInterface.Get(playerInterfaceName, "CanGoNext").to!bool;
			const newCanPrev = mpInterface.Get(playerInterfaceName, "CanGoPrevious").to!bool;
			const newCanPlay = mpInterface.Get(playerInterfaceName, "CanPlay").to!bool;
			const newCanPause = mpInterface.Get(playerInterfaceName, "CanPause").to!bool;
			const newIsPlaying = mpInterface.Get(playerInterfaceName,
					"PlaybackStatus").to!string == "Playing";
			auto pos = mpInterface.Get(playerInterfaceName, "Position").to!(Variant!DBusAny);
			const newLocation = pos.data.typeIsIntegral ? pos.data.to!long : 0;

			if (newLocation != 0)
			{
				if (!progress.running)
					progress.start();
				progress.setTimeElapsed(newLocation.usecs);
			}

			if (isPlaying)
			{
				if (auto length = "mpris:length" in song)
					songLength = length.data.to!long.usecs;
				else
					songLength = Duration.zero;
			}

			if (newCanNext != canNext || newCanPrev != canPrev || newCanPause != canPause
					|| newCanPlay != canPlay || newIsPlaying != isPlaying || updateLabel(song))
			{
				canNext = newCanNext;
				canPrev = newCanPrev;
				canPlay = newCanPlay;
				canPause = newCanPause;
				isPlaying = newIsPlaying;
				queueRedraw();
			}
		}
		catch (DBusException)
		{
			mpInterface = null;
			playerInterface = null;
		}
	}

	private bool updateLabel(Variant!DBusAny[string] metadata)
	{
		auto artist = "xesam:artist" in metadata;
		auto title = "xesam:title" in metadata;

		string song;

		if (artist)
		{
			if (artist.data.type == 'a' && artist.data.signature == "s")
				song = artist.data.to!(string[]).join(", ") ~ " - ";
			else if (artist.data.type == 's')
				song = artist.data.to!string ~ " - ";
		}

		if (title)
			song ~= title.data.get!string;
		else if (song.length)
			song.length -= 3;

		if (!song.length)
			song = "Unknown";

		if (song == label)
			return false;

		label = song;
		progress.reset();
		return true;
	}

	void mouseDown(bool vertical, int x, int y, int button)
	{
		if (button != 1)
			return;
		try
		{
			if (x < 24)
				previous();
			else if (x < 24 * 2)
			{
				playPause();
				isPlaying = !isPlaying;
			}
			else if (x < 24 * 3)
				next();
			else
				return;
		}
		catch (DBusException)
		{
			mpInterface = null;
			playerInterface = null;
		}

		queueRedraw();
	}

	void mouseUp(bool vertical, int x, int y, int button)
	{
	}

	void mouseMove(bool vertical, int x, int y)
	{
	}

	void changeName(string owner, string old, string new_)
	{
		if (!owner.isMprisName)
			return;

		if (!old.length && new_.length)
			addName(owner);
		else if (old.length && !new_.length)
			removeName(owner);
	}

	void addName(string name)
	{
		stderr.writeln("Added name: ", name);
		if (!names.canFind(name))
			names ~= name;
	}

	void removeName(string name)
	{
		stderr.writeln("Removed name: ", name);
		names = names.remove!(a => a == name);

		if (name == activeName)
		{
			activeName = null;
			mpInterface = null;
			playerInterface = null;

			searchActivePlayer();
		}
	}

	void registerNames()
	{
		MessageRouter router = new MessageRouter();
		registerMethods(router, ObjectPath("/org/webfreak/DWinBar"),
				interfaceName("org.webfreak.DWinBar.ActiveMprisController"), activeController);
		registerRouter(sessionBus.conn, router);
		enforce(requestName(sessionBus.conn, busName("org.webfreak.DWinBar")));

		sessionBus.onNameChange(&changeName);
		names = sessionBus.listNames().filter!isMprisName.array;
		searchActivePlayer();
	}

	void searchActivePlayer()
	{
		if (activeName.length && mpInterface)
		{
			try
			{
				if (mpInterface.Get(playerInterfaceName, "PlaybackStatus").to!string == "Playing")
					return;
			}
			catch (Exception e)
			{
				stderr.writeln("Disconnecting player ", activeName, ": ", e.msg);
				activeName = null;
				mpInterface = null;
				playerInterface = null;
			}
		}

		foreach (name; names)
		{
			auto i = new PathIface(sessionBus.conn, busName(name), mprisObjectPath,
					interfaceName("org.freedesktop.DBus.Properties"));

			string playbackStatus;

			try
			{
				playbackStatus = i.Get(playerInterfaceName, "PlaybackStatus").to!string;
			}
			catch (Exception e)
			{
				names = names.remove!(a => a == name);
				stderr.writeln(name, " is not a valid mpris player! ", e.msg);
				break;
			}

			if (playbackStatus == "Playing")
			{
				activeName = name;
				mpInterface = i;
				playerInterface = new PathIface(sessionBus.conn, busName(name),
						mprisObjectPath, playerInterfaceName);
				break;
			}
		}
	}

	bool spotify() const @property
	{
		return activeName == "org.mpris.MediaPlayer2.spotify";
	}

private:
	FontFamily font;
	PathIface mpInterface, playerInterface;
	BusName dest;
	string label;
	bool isPlaying, canPlay, canPause, canPrev, canNext, force;
	StopWatch progress;
	Duration songLength;
	IFImage prevIcon, pauseIcon, playIcon, nextIcon;
	StopWatch updateClock;
	int tick;
	ActiveMprisController activeController;

	string[] names;
	string activeName;
}

bool isMprisName(string name)
{
	return name.startsWith("org.mpris.MediaPlayer2.");
}
