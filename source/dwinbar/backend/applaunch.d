module dwinbar.backend.applaunch;

import core.sys.posix.unistd;

void spawnProcessDetach(in char[][] args)
{
	assert(args.length >= 1);
	char*[] argv;
	foreach (arg; args)
		argv ~= cast(char*)(arg ~ 0).ptr;
	execvp(argv[0], argv.ptr);
	throw new Exception("Failed to spawn process");
}
