namespace StormTactics.Server;

using System;
using System.IO;
using Sedulous.Net.HTTP;

/// Main game server class. Wraps HttpServer and owns all server components.
class GameServer
{
	private HttpServer mHttpServer = new .() ~ delete _;
	private AuthManager mAuthManager = new .() ~ delete _;
	private SessionManager mSessionManager = new .() ~ delete _;
	private PlayerDataStore mDataStore = new .() ~ delete _;
	private AuthRoutes mAuthRoutes ~ delete _;
	private PlayerRoutes mPlayerRoutes ~ delete _;
	private ServerConfig mConfig;

	public uint16 Port => mConfig.mPort;

	/// Initialize the server with the given configuration.
	public Result<void> Initialize(ServerConfig config)
	{
		mConfig = config;

		// Ensure data directory exists
		Directory.CreateDirectory(config.mDataDir);

		// Initialize components
		mAuthManager.Initialize(config.mDataDir);
		mSessionManager.Initialize(config.mSessionTimeoutSeconds);
		mDataStore.Initialize(config.mDataDir);

		// Register routes
		mAuthRoutes = new AuthRoutes(mAuthManager, mSessionManager, mDataStore);
		mAuthRoutes.Register(mHttpServer);
		mPlayerRoutes = new PlayerRoutes(mSessionManager, mDataStore);
		mPlayerRoutes.Register(mHttpServer);

		Console.WriteLine("[Server] Initialized (data dir: {})", config.mDataDir);
		return .Ok;
	}

	/// Start listening for connections.
	public Result<void> Start()
	{
		if (mHttpServer.Start(mConfig.mPort) case .Err(let err))
		{
			Console.WriteLine("[Server] ERROR: Failed to start on port {} — {}", mConfig.mPort, err);
			return .Err;
		}

		Console.WriteLine("[Server] Listening on port {}", mConfig.mPort);
		return .Ok;
	}

	/// Process pending connections and clean up expired sessions.
	/// Call this in the main loop.
	public void Update()
	{
		mHttpServer.Update();
		mSessionManager.CleanExpiredSessions();
	}

	/// Stop the server.
	public void Stop()
	{
		mHttpServer.Stop();
		Console.WriteLine("[Server] Stopped");
	}
}
