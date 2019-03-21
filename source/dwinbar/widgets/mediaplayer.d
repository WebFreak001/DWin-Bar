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

import tinyevent;

class MprisMediaPlayerWidget : Widget, IMouseWatch
{
	this()
	{
		path = "/org/mpris/MediaPlayer2";
		iface = "org.mpris.MediaPlayer2.Player";
	}

	this(FontFamily font, string dest, string path = "/org/mpris/MediaPlayer2",
			string iface = "org.mpris.MediaPlayer2.Player")
	{
		this.font = font;
		this.dest = dest;
		this.path = path;
		this.iface = iface;
		sessionBus.attach();
		prevIcon = read_image("res/icon/skip-previous.png").premultiply;
		pauseIcon = read_image("res/icon/pause.png").premultiply;
		playIcon = read_image("res/icon/play.png").premultiply;
		nextIcon = read_image("res/icon/skip-next.png").premultiply;
		updateClock.start();
	}

	override void loadBase(WidgetConfig config)
	{
		this.font = config.bar.fontFamily;

		sessionBus.attach();
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
		case "dest":
			dest = value.to!string;
			return true;
		case "spotify":
			spotify = value.to!bool;
			return true;
		default:
			return false;
		}
	}

	override int width(bool) const
	{
		if (!mpInterface || !playerInterface)
			return 0;
		return 24 * 3 + 8 + cast(int) ceil(measureText(cast() font, 1, label)[0]);
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
			stderr.writeln("Progress: ", progress);
			int width = cast(int)(canvas.w * progress);
			if (width >= 0 && width <= canvas.w)
			{
				if (width > 1)
					canvas.fillRect(1, canvas.h - 3, width - 1, 1, cast(ubyte[4])[
							0xFF, 0x65, 0x00, 0xFF
							]);
				canvas.fillRect(0, canvas.h - 2, width, 2, cast(ubyte[4])[
						0xFF, 0x65, 0x00, 0xFF
						]);
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
		if (mpInterface && playerInterface)
			return true;

		try
		{
			mpInterface = new PathIface(sessionBus.conn, dest, path, "org.freedesktop.DBus.Properties");
			playerInterface = new PathIface(sessionBus.conn, dest, path, iface);
			return true;
		}
		catch (Exception)
		{
			return false;
		}
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
			else if (progress.running)
				progress.stop();
			tick = 0;
		}
		else if (!isPlaying && progress.running)
			progress.stop();

		if (songLength != Duration.zero && isPlaying)
			queueRedraw();

		try
		{
			auto song = mpInterface.Get(iface, "Metadata").to!(Variant!DBusAny[string]);
			const newCanNext = mpInterface.Get(iface, "CanGoNext").to!bool;
			const newCanPrev = mpInterface.Get(iface, "CanGoPrevious").to!bool;
			const newCanPlay = mpInterface.Get(iface, "CanPlay").to!bool;
			const newCanPause = mpInterface.Get(iface, "CanPause").to!bool;
			const newIsPlaying = mpInterface.Get(iface, "PlaybackStatus").to!string == "Playing";
			const newLocation = mpInterface.Get(iface, "Position").to!long;

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
			song = artist.data.to!(string[]).join(", ") ~ " - ";

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

private:
	FontFamily font;
	PathIface mpInterface, playerInterface;
	string dest, path, iface;
	string label;
	bool isPlaying, canPlay, canPause, canPrev, canNext, force;
	StopWatch progress;
	Duration songLength;
	bool spotify;
	IFImage prevIcon, pauseIcon, playIcon, nextIcon;
	StopWatch updateClock;
	int tick;
}
