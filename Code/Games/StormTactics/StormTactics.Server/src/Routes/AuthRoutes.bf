namespace StormTactics.Server;

using System;
using Sedulous.Net.HTTP;

/// Registers auth-related HTTP route handlers.
class AuthRoutes
{
	private AuthManager mAuth;
	private SessionManager mSessions;
	private PlayerDataStore mDataStore;

	public this(AuthManager auth, SessionManager sessions, PlayerDataStore dataStore)
	{
		mAuth = auth;
		mSessions = sessions;
		mDataStore = dataStore;
	}

	public void Register(HttpServer server)
	{
		server.Post("/api/auth/register", new => OnRegister);
		server.Post("/api/auth/login", new => OnLogin);
	}

	private void OnRegister(HttpRequest req, HttpResponse resp)
	{
		let body = scope String();
		GetRequestBody(req, body);

		let username = scope String();
		let password = scope String();
		if (!JsonHelper.GetString(body, "username", username) ||
			!JsonHelper.GetString(body, "password", password))
		{
			resp.StatusCode = .BadRequest;
			let json = scope String();
			JsonHelper.BuildError(json, "username and password required");
			resp.SetJsonBody(json);
			return;
		}

		if (username.Length < 1 || password.Length < 3)
		{
			resp.StatusCode = .BadRequest;
			let json = scope String();
			JsonHelper.BuildError(json, "username must be non-empty, password at least 3 characters");
			resp.SetJsonBody(json);
			return;
		}

		if (mAuth.HasAccount(username))
		{
			resp.StatusCode = .Conflict;
			let json = scope String();
			JsonHelper.BuildError(json, "Username already exists");
			resp.SetJsonBody(json);
			return;
		}

		if (mAuth.Register(username, password) case .Ok(let account))
		{
			// Create player data
			let playerData = mDataStore.CreateNewPlayer(account.mPlayerId);
			delete playerData;

			// Create session
			let session = mSessions.CreateSession(account.mPlayerId, account.mUsername);

			resp.StatusCode = .Created;
			let json = scope String();
			JsonHelper.BuildObjectRaw(json,
				("success", "true", false),
				("token", session.mToken, true),
				("playerId", account.mPlayerId, true));
			resp.SetJsonBody(json);
		}
		else
		{
			resp.StatusCode = .InternalServerError;
			let json = scope String();
			JsonHelper.BuildError(json, "Registration failed");
			resp.SetJsonBody(json);
		}
	}

	private void OnLogin(HttpRequest req, HttpResponse resp)
	{
		let body = scope String();
		GetRequestBody(req, body);

		let username = scope String();
		let password = scope String();
		if (!JsonHelper.GetString(body, "username", username) ||
			!JsonHelper.GetString(body, "password", password))
		{
			resp.StatusCode = .BadRequest;
			let json = scope String();
			JsonHelper.BuildError(json, "username and password required");
			resp.SetJsonBody(json);
			return;
		}

		if (mAuth.Login(username, password) case .Ok(let account))
		{
			let session = mSessions.CreateSession(account.mPlayerId, account.mUsername);

			resp.StatusCode = .OK;
			let json = scope String();
			JsonHelper.BuildObjectRaw(json,
				("success", "true", false),
				("token", session.mToken, true),
				("playerId", account.mPlayerId, true));
			resp.SetJsonBody(json);
		}
		else
		{
			resp.StatusCode = .Unauthorized;
			let json = scope String();
			JsonHelper.BuildError(json, "Invalid credentials");
			resp.SetJsonBody(json);
		}
	}

	private static void GetRequestBody(HttpRequest req, String outStr)
	{
		if (req.Body.Count > 0)
			outStr.Append((char8*)req.Body.Ptr, req.Body.Count);
	}
}
