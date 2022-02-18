module dwinbar.backend.dbus;

public import ddbus;
import ddbus.c_lib;

import core.thread;
import core.time;

import std.datetime.stopwatch;
import std.format;
import std.string;
import std.typecons;

struct SignalSubscription
{
	const(char)* rule;
	const(char)* iface, signal;
	void delegate(scope ref Message msg) callback;
}

struct ConnectionPool
{
	static immutable dbusName = busName("org.freedesktop.DBus");
	static immutable dbusPath = ObjectPath("/org/freedesktop/DBus");
	static immutable dbusIface = interfaceName("org.freedesktop.DBus");

	DBusBusType type;
	PathIface dbus;
	SignalSubscription[] signals;

	this(DBusBusType type)
	{
		this.type = type;
	}

	bool connected;

	Connection conn;

	void attach()
	{
		if (connected)
			return;
		conn = connectToBus(type);
		dbus = new PathIface(conn, dbusName, dbusPath, dbusIface);
		connected = true;
	}

	void update(Duration timeout = Duration.zero)
	{
		if (!connected)
			return;
		if (!dbus_connection_read_write(conn.conn, cast(int) timeout.total!"msecs"))
			throw new Exception("tick break");

		do
		{
			dbus_connection_dispatch(conn.conn);
			auto msg = dbus_connection_pop_message(conn.conn);
			if (msg == null)
				break;
			scope message = Message(msg);

			foreach (sub; signals)
			{
				if (dbus_message_is_signal(msg, sub.iface, sub.signal))
					sub.callback(message);
				// no break because we might have multiple signals handling this
			}
		}
		while (true);
	}

	bool onSignal(BusName sender, ObjectPath path, InterfaceName iface,
			string member, void delegate(scope ref Message msg) callback)
	{
		if (!connected)
			throw new Exception("Attempted to subscribe to signal when not connected");

		auto rule = format!`type='signal',sender='%s',interface='%s',member='%s',path='%s'`(
				cast(string) sender, cast(string) iface, member, cast(string) path).toStringz;

		DBusError error;
		dbus_bus_add_match(conn.conn, rule, &error);

		if (dbus_error_is_set(&error))
			return false;
		else
		{
			signals ~= SignalSubscription(rule, (cast(string) iface).dup.toStringz,
					member.toStringz, callback);
			return true;
		}
	}

	string[] listNames()
	{
		if (!connected)
			throw new Exception("Attempted to list dbus names when not connected");

		return dbus.ListNames().to!(string[]);
	}

	bool onNameChange(void delegate(string, string, string) callback)
	{
		return onSignal(dbusName, dbusPath, dbusIface, "NameOwnerChanged", (scope ref msg) {
			auto t = msg.readTuple!(Tuple!(string, string, string));
			callback(t[0].idup, t[1].idup, t[2].idup);
		});
	}
}

ConnectionPool sessionBus = ConnectionPool(DBusBusType.DBUS_BUS_SESSION);
ConnectionPool systemBus = ConnectionPool(DBusBusType.DBUS_BUS_SYSTEM);

void updateDBus(Duration timeout = Duration.zero)
{
	if (sessionBus.connected && systemBus.connected)
	{
		sessionBus.update(timeout / 2);
		systemBus.update(timeout / 2);
	}
	else if (sessionBus.connected)
	{
		sessionBus.update(timeout);
	}
	else if (systemBus.connected)
	{
		systemBus.update(timeout);
	}
}

void updateDBusWaiting(Duration waitAmount)
{
	if (waitAmount == Duration.zero)
		return updateDBus();

	StopWatch total;
	total.start();
	while (total.peek < waitAmount)
	{
		StopWatch sw;
		sw.start();
		updateDBus(waitAmount);
		sw.stop();
		if (sw.peek < 5.msecs && waitAmount - total.peek >= 5.msecs)
			Thread.sleep(5.msecs - sw.peek);
	}
}
