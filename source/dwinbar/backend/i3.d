module dwinbar.backend.i3;

import dwinbar.backend.xbackend;

import std.socket;

enum I3MessageType : uint
{
	COMMAND,
	GET_WORKSPACES,
	SUBSCRIBE,
	GET_OUTPUTS,
	GET_TREE,
	GET_MARKS,
	GET_BAR_CONFIG,
	GET_VERSION,
	GET_BINDING_MODES
}

align(1) private struct I3Header
{
align(1):
	char[6] magic = "i3-ipc";
	uint dataLength;
	I3MessageType type;
}

struct I3Utils
{
	this(XBackend x)
	{
		this.x = x;
		checkAvailable();
		if (available)
		{
			connection = new Socket(AddressFamily.UNIX, SocketType.STREAM);
			connection.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
			connection.connect(new UnixAddress(socketPath));
		}
	}

	bool checkAvailable()
	{
		Atom returnType;
		int format;
		ulong number, bytesAfter;
		ubyte* strs;

		if (XGetWindowProperty(x.display, x.root, XAtom[AtomName.I3_SOCKET_PATH],
				0, 64, false, AnyPropertyType, &returnType, &format, &number,
				&bytesAfter, cast(ubyte**)&strs) == 0 && format == 8)
		{
			socketPath = cast(string) strs[0 .. number].idup;
			return available = true;
		}
		return available = false;
	}

	void send(I3MessageType type, ubyte[] message)
	{
		I3Header header;
		header.type = type;
		header.dataLength = cast(uint) message.length;
		connection.send((cast(void*)&header)[0 .. I3Header.sizeof]);
		if (message.length)
			connection.send(message);
	}

	void sendCommand(string command)
	{
		send(I3MessageType.COMMAND, cast(ubyte[]) command);
	}

	XBackend x;
	bool available;
	string socketPath;
	Socket connection;
}
