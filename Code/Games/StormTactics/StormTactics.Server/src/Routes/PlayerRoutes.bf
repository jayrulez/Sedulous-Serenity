namespace StormTactics.Server;

using System;
using Sedulous.Net.HTTP;

/// Registers player data HTTP route handlers.
class PlayerRoutes
{
	private SessionManager mSessions;
	private PlayerDataStore mDataStore;

	public this(SessionManager sessions, PlayerDataStore dataStore)
	{
		mSessions = sessions;
		mDataStore = dataStore;
	}

	public void Register(HttpServer server)
	{
		server.Get("/api/player/data", new => OnGetData);
		server.Post("/api/player/save", new => OnSaveData);
	}

	private void OnGetData(HttpRequest req, HttpResponse resp)
	{
		let session = ValidateAuth(req, resp);
		if (session == null) return;

		let playerData = mDataStore.LoadPlayerData(session.mPlayerId);
		if (playerData == null)
		{
			resp.StatusCode = .NotFound;
			let json = scope String();
			JsonHelper.BuildError(json, "Player data not found");
			resp.SetJsonBody(json);
			return;
		}
		defer delete playerData;

		let xml = scope String();
		PlayerDataStore.SerializeToXml(playerData, xml);

		resp.StatusCode = .OK;
		resp.SetHeader("Content-Type", "application/xml");
		resp.SetBody(xml);
	}

	private void OnSaveData(HttpRequest req, HttpResponse resp)
	{
		let session = ValidateAuth(req, resp);
		if (session == null) return;

		let body = scope String();
		if (req.Body.Count > 0)
			body.Append((char8*)req.Body.Ptr, req.Body.Count);

		if (body.IsEmpty)
		{
			resp.StatusCode = .BadRequest;
			let json = scope String();
			JsonHelper.BuildError(json, "Empty body");
			resp.SetJsonBody(json);
			return;
		}

		let playerData = PlayerDataStore.DeserializeFromXml(body);
		if (playerData == null)
		{
			resp.StatusCode = .BadRequest;
			let json = scope String();
			JsonHelper.BuildError(json, "Invalid player data XML");
			resp.SetJsonBody(json);
			return;
		}
		defer delete playerData;

		if (mDataStore.SavePlayerData(session.mPlayerId, playerData) case .Err)
		{
			resp.StatusCode = .InternalServerError;
			let json = scope String();
			JsonHelper.BuildError(json, "Failed to save player data");
			resp.SetJsonBody(json);
			return;
		}

		resp.StatusCode = .OK;
		let json = scope String();
		JsonHelper.BuildSuccess(json);
		resp.SetJsonBody(json);
	}

	/// Extract and validate the Authorization: Bearer <token> header.
	private Session ValidateAuth(HttpRequest req, HttpResponse resp)
	{
		let authHeader = scope String();
		if (!req.Headers.Get("Authorization", authHeader))
		{
			resp.StatusCode = .Unauthorized;
			let json = scope String();
			JsonHelper.BuildError(json, "Missing Authorization header");
			resp.SetJsonBody(json);
			return null;
		}

		if (!authHeader.StartsWith("Bearer ") || authHeader.Length < 8)
		{
			resp.StatusCode = .Unauthorized;
			let json = scope String();
			JsonHelper.BuildError(json, "Invalid Authorization format");
			resp.SetJsonBody(json);
			return null;
		}

		let token = authHeader.Substring(7);
		let session = mSessions.ValidateSession(token);
		if (session == null)
		{
			resp.StatusCode = .Unauthorized;
			let json = scope String();
			JsonHelper.BuildError(json, "Invalid or expired session");
			resp.SetJsonBody(json);
			return null;
		}

		return session;
	}
}
