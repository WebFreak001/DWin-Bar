module dwinbar.webserver;

import std.base64;
import std.concurrency;
import std.conv;
import std.format;
import std.typecons;
import std.uri;

import vibe.vibe;

import core.thread;

__gshared string clientId, clientSecret, redirectURL;
__gshared AuthToken spotifyToken;

Tid webServerThread;

struct DoExit
{
}

void vibeMain()
{
	auto settings = new HTTPServerSettings;
	settings.options = HTTPServerOption.reusePort;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	settings.port = 3007;

	auto router = new URLRouter;
	router.get("/spotify/auth", &getSpotifyAuth);
	router.get("/spotify", &getSpotify);

	if (existsFile("spotify-auth.json"))
	{
		spotifyToken = deserializeJson!AuthToken(
				parseJsonString(readFileUTF8("spotify-auth.json"), "spotify-auth.json"));
		refreshSpotify();
	}

	runTask({ receiveOnly!DoExit(); exitEventLoop(true); });

	listenHTTP(settings, router);

	runEventLoop();
}

void startSpotifyWebServer()
{
	if (clientId.length && clientSecret.length && redirectURL.length)
		webServerThread = spawn(&vibeMain);
}

void getSpotify(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.redirect(format!"https://accounts.spotify.com/authorize?client_id=%s&response_type=code&redirect_uri=%s&scope=user-read-playback-state"(
			clientId, encodeComponent(redirectURL)));
}

struct AuthToken
{
	@name("access_token")
	string accessToken;
	@name("refresh_token")
	string refreshToken;

	string scope_;
	@name("expires_in")
	int expiresIn;
}

void refreshSpotify() @trusted
{
	int status;
	Json ret;

	requestHTTP("https://accounts.spotify.com/api/token", (scope req) {
		req.method = HTTPMethod.POST;
		req.writeFormBody([
				"grant_type": "refresh_token",
				"refresh_token": spotifyToken.refreshToken,
				"client_id": clientId,
				"client_secret": clientSecret
			]);
	}, (scope res) { status = res.statusCode; ret = res.readJson; });
	if (status != 200)
	{
		logError("Failed refreshing spotify token: %s", ret);
		return;
	}
	spotifyToken.accessToken = ret["access_token"].get!string;
	spotifyToken.scope_ = ret["scope"].get!string;
	spotifyToken.expiresIn = ret["expires_in"].get!int;
	rearmRefresh();
}

void rearmRefresh() @trusted
{
	setTimer((spotifyToken.expiresIn * 2 / 3).seconds, () @safe nothrow{
		try
		{
			refreshSpotify();
		}
		catch (Exception e)
		{
			logError("Failed to refresh spotify: %s", e.msg);
		}
	});
}

void getSpotifyAuth(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	string code = req.query.get("code", "");
	string error = req.query.get("error", "");

	if (!code.length && error.length)
	{
		res.writeBody("You rejected spotify authentication. Song progress will not be displayed on the bar.",
				"text/plain");
	}
	else
	{
		int status;
		Json data;
		requestHTTP("https://accounts.spotify.com/api/token", (scope req) {
			req.method = HTTPMethod.POST;
			req.writeFormBody([
					"grant_type": "authorization_code",
					"code": code,
					"redirect_uri": redirectURL,
					"client_id": clientId,
					"client_secret": clientSecret
				]);
		}, (scope res) { status = res.statusCode; data = res.readJson(); });

		if (status != 200)
		{
			res.writeBody("Failed to authenticate spotify. Please try again. Check the console for details.",
					"text/plain");
			logError("Spotify failure: %s", data);
			return;
		}

		spotifyToken = deserializeJson!AuthToken(data);
		logInfo("Token: %s", spotifyToken);

		writeFileUTF8(NativePath("spotify-auth.json"), serializeToJsonString(spotifyToken));

		res.writeBody("<!DOCTYPE html><html><head><title>Success</title><script>window.close()</script></head><body>Success. You can close the window now.</body></html>",
				"text/html");

		rearmRefresh();
	}
}

struct SpotifyUserStatus
{
@optional:
	long timestamp;
	Nullable!long progress_ms;
	bool is_playing;
	@name("currently_playing_type")
	string currentlyPlayingType;
}

SpotifyUserStatus getSpotifyCurrentlyPlaying()
{
	if (!spotifyToken.accessToken.length)
		return SpotifyUserStatus.init;

	try
	{
		int status;
		Json ret;
		requestHTTP("https://api.spotify.com/v1/me/player", (scope req) {
			req.headers.addField("Authorization", "Bearer " ~ spotifyToken.accessToken);
		}, (scope res) { status = res.statusCode; ret = res.readJson; });

		if (status != 200)
		{
			logError("Failed reading spotify status: %s", ret);
			return SpotifyUserStatus.init;
		}
		return deserializeJson!SpotifyUserStatus(ret);
	}
	catch (Exception e)
	{
		logError("Exception reading spotify status: %s", e);
		return SpotifyUserStatus.init;
	}
}
