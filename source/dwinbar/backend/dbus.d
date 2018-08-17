module dwinbar.backend.dbus;

public import ddbus;
import ddbus.c_lib;

struct ConnectionPool
{
	DBusBusType type;

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
		connected = true;
	}

	void update()
	{
		if (!connected)
			return;
		if (!dbus_connection_read_write_dispatch(conn.conn, 0))
			throw new Exception("tick break");
	}
}

ConnectionPool sessionBus = ConnectionPool(DBusBusType.DBUS_BUS_SESSION);
ConnectionPool systemBus = ConnectionPool(DBusBusType.DBUS_BUS_SYSTEM);

void updateDBus()
{
	sessionBus.update();
	systemBus.update();
}
