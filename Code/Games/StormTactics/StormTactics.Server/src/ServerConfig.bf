namespace StormTactics.Server;

using System;

/// Server configuration settings.
class ServerConfig
{
	public uint16 mPort = 8080;
	public String mDataDir = new .("./server_data") ~ delete _;
	public int32 mSessionTimeoutSeconds = 3600; // 1 hour
}
