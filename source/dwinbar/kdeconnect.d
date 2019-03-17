module dwinbar.kdeconnect;

import dwinbar.backend.dbus;

import std.stdio;

import std.xml;

struct KDEConnectDevice
{
	string id;
	PathIface properties;
	PathIface device;
	PathIface battery;

	bool chargingCache;
	int batteryCache;

	bool isReachable()
	{
		try
		{
			return properties.Get("org.kde.kdeconnect.device", "isReachable").to!DBusAny
				.get!bool;
		}
		catch (Exception e)
		{
			return false;
		}
	}

	bool isCharging()
	{
		try
		{
			return chargingCache = battery.isCharging().to!bool;
		}
		catch (Exception)
		{
			return chargingCache;
		}
	}

	int charge() @property
	{
		try
		{
			return batteryCache = battery.charge().to!int;
		}
		catch (Exception)
		{
			return batteryCache;
		}
	}

	static KDEConnectDevice[] listDevices()
	{
		try
		{
			sessionBus.attach();
			auto conn = new PathIface(sessionBus.conn, "org.kde.kdeconnect",
					"/modules/kdeconnect/devices", "org.freedesktop.DBus.Introspectable");

			KDEConnectDevice[] ret;

			auto xml = new DocumentParser(conn.Introspect().to!string);
			xml.onStartTag["node"] = (ElementParser xml) {
				string id = xml.tag.attr["name"];
				try
				{
					auto path = "/modules/kdeconnect/devices/" ~ id;
					PathIface properties = new PathIface(sessionBus.conn,
							"org.kde.kdeconnect", path, "org.freedesktop.DBus.Properties");
					PathIface device = new PathIface(sessionBus.conn,
							"org.kde.kdeconnect", path, "org.kde.kdeconnect.device");
					PathIface battery = new PathIface(sessionBus.conn,
							"org.kde.kdeconnect", path, "org.kde.kdeconnect.device.battery");
					ret ~= KDEConnectDevice(id, properties, device, battery);
				}
				catch (Exception e)
				{
					stderr.writeln("Failed to attach to device " ~ id ~ ": " ~ e.msg);
				}
			};
			xml.parse();

			return ret;
		}
		catch (Exception e)
		{
			stderr.writeln(e);
			return null;
		}
	}
}
