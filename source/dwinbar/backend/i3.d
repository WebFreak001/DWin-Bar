module dwinbar.backend.i3;

import dwinbar.backend.xbackend;

import std.socket;
import std.json;

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

struct WorkspaceInfo
{
	string name;
	bool visible, focused, urgent;
	string output;
}

private union MessageContainer
{
	ubyte[I3Header.sizeof] headerBuffer;
	I3Header header;
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

	WorkspaceInfo[] getWorkspaces(bool tried = false)
	{
		MessageContainer m;

		connection.blocking = false;
		while (connection.receive(m.headerBuffer[]) > 0)
		{
		}
		connection.blocking = true;

		send(I3MessageType.GET_WORKSPACES, []);

		ptrdiff_t index;
		while (index < m.headerBuffer.length)
		{
			auto len = connection.receive(m.headerBuffer[index .. $]);
			if (len <= 0)
				throw new Exception("Disconnected");
			index += len;
		}

		ubyte[] data = new ubyte[m.header.dataLength];
		index = 0;
		while (index < data.length)
		{
			auto len = connection.receive(data[index .. $]);
			if (len <= 0)
				throw new Exception("Disconnected");
			index += len;
		}

		JSONValue[] workspaces = parseJSON(cast(string) data).array;
		WorkspaceInfo[] ret;
		foreach (workspace; workspaces)
		{
			if ("success" in workspace)
			{
				if (tried)
					return [];
				return getWorkspaces(true);
			}
			//dfmt off
			ret ~= WorkspaceInfo(
				workspace["name"].str,
				workspace["visible"].boolean,
				workspace["focused"].boolean,
				workspace["urgent"].boolean,
				workspace["output"].str
			);
			//dfmt on
		}
		return ret;
	}

	XBackend x;
	bool available;
	string socketPath;
	Socket connection;
}
