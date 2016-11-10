module dwinbar.backend.applaunch;

import std.process;
import core.sys.posix.unistd;
import std.stdio;

void spawnProcessDetach(in char[][] args, File stdin = std.stdio.stdin,
		File stdout = std.stdio.stdout, File stderr = std.stdio.stderr,
		const string[string] env = null, Config config = Config.none, in char[] workDir = null) @safe
{
	auto pid = fork();
	if (pid < 0)
		throw new Exception("Failed to fork");
	else if (pid == 0)
	{
		auto child = spawnProcess(args, stdin, stdout, stderr, env, config, workDir);
		_exit(child.wait);
	}
}
