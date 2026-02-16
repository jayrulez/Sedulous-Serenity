namespace StormTactics.Client;

using System;
using Sedulous.Net.HTTP;
using Sedulous.Serialization;
using Sedulous.Serialization.Xml;
using Sedulous.Xml;
using StormTactics.Core;

/// Handles save/load via the StormTactics server over HTTP.
/// Replaces SaveManager when running in server mode.
class ServerSaveManager
{
	private String mServerHost = new .("127.0.0.1") ~ delete _;
	private uint16 mServerPort = 8080;
	private String mSessionToken = new .() ~ delete _;
	private String mPlayerId = new .() ~ delete _;
	private PlayerSaveData mSaveData ~ delete _;
	private HttpClient mHttpClient = new .() ~ delete _;
	private bool mIsAuthenticated;

	public PlayerSaveData SaveData => mSaveData;
	public bool IsAuthenticated => mIsAuthenticated;
	public StringView PlayerId => mPlayerId;

	/// Configure the server connection.
	public void Initialize(StringView host, uint16 port)
	{
		mServerHost.Set(host);
		mServerPort = port;
		mHttpClient.TimeoutMs = 10000;
	}

	/// Register a new account. On success, loads player data.
	public Result<void> Register(StringView username, StringView password)
	{
		let json = scope String();
		json.AppendF("{{\"username\":\"{}\",\"password\":\"{}\"}}", username, password);

		switch (mHttpClient.Post(mServerHost, mServerPort, "/api/auth/register", json, "application/json"))
		{
		case .Ok(let response):
			defer delete response;

			if ((int32)response.StatusCode >= 200 && (int32)response.StatusCode < 300)
			{
				let body = scope String();
				response.GetBodyString(body);
				return ParseAuthResponse(body);
			}
			else
			{
				let body = scope String();
				response.GetBodyString(body);
				Console.WriteLine("[ServerSave] Register failed: {}", body);
				return .Err;
			}
		case .Err(let err):
			Console.WriteLine("[ServerSave] Register connection error: {}", err);
			return .Err;
		}
	}

	/// Login with existing credentials. On success, loads player data.
	public Result<void> Login(StringView username, StringView password)
	{
		let json = scope String();
		json.AppendF("{{\"username\":\"{}\",\"password\":\"{}\"}}", username, password);

		switch (mHttpClient.Post(mServerHost, mServerPort, "/api/auth/login", json, "application/json"))
		{
		case .Ok(let response):
			defer delete response;

			if ((int32)response.StatusCode == 200)
			{
				let body = scope String();
				response.GetBodyString(body);
				return ParseAuthResponse(body);
			}
			else
			{
				let body = scope String();
				response.GetBodyString(body);
				Console.WriteLine("[ServerSave] Login failed: {}", body);
				return .Err;
			}
		case .Err(let err):
			Console.WriteLine("[ServerSave] Login connection error: {}", err);
			return .Err;
		}
	}

	/// Save current player data to the server.
	public Result<void> Save()
	{
		if (mSaveData == null || !mIsAuthenticated)
			return .Err;

		let xml = scope String();
		SerializeToXml(mSaveData, xml);

		let request = scope HttpRequest(.POST, "/api/player/save");
		request.SetHeader("Authorization", scope $"Bearer {mSessionToken}");
		request.SetHeader("Content-Type", "application/xml");
		request.SetBody(xml);

		switch (mHttpClient.Send(mServerHost, mServerPort, request))
		{
		case .Ok(let response):
			defer delete response;
			if ((int32)response.StatusCode == 200)
			{
				Console.WriteLine("[ServerSave] Saved successfully");
				return .Ok;
			}
			else
			{
				let body = scope String();
				response.GetBodyString(body);
				Console.WriteLine("[ServerSave] Save failed: {}", body);
				return .Err;
			}
		case .Err(let err):
			Console.WriteLine("[ServerSave] Save connection error: {}", err);
			return .Err;
		}
	}

	/// Load player data from the server.
	public Result<void> Load()
	{
		if (!mIsAuthenticated)
			return .Err;

		let request = scope HttpRequest(.GET, "/api/player/data");
		request.SetHeader("Authorization", scope $"Bearer {mSessionToken}");

		switch (mHttpClient.Send(mServerHost, mServerPort, request))
		{
		case .Ok(let response):
			defer delete response;

			if ((int32)response.StatusCode == 200)
			{
				let body = scope String();
				response.GetBodyString(body);

				let data = DeserializeFromXml(body);
				if (data == null)
				{
					Console.WriteLine("[ServerSave] Failed to parse player data XML");
					return .Err;
				}

				delete mSaveData;
				mSaveData = data;
				Console.WriteLine("[ServerSave] Player data loaded");
				return .Ok;
			}
			else
			{
				let body = scope String();
				response.GetBodyString(body);
				Console.WriteLine("[ServerSave] Load failed: {}", body);
				return .Err;
			}
		case .Err(let err):
			Console.WriteLine("[ServerSave] Load connection error: {}", err);
			return .Err;
		}
	}

	/// Logout and clear session.
	public void Logout()
	{
		mSessionToken.Clear();
		mPlayerId.Clear();
		mIsAuthenticated = false;
		delete mSaveData;
		mSaveData = null;
	}

	/// Parse auth response JSON, extract token + playerId, then load player data.
	private Result<void> ParseAuthResponse(StringView body)
	{
		let token = scope String();
		let playerId = scope String();

		if (!GetJsonString(body, "token", token) || !GetJsonString(body, "playerId", playerId))
		{
			Console.WriteLine("[ServerSave] Failed to parse auth response");
			return .Err;
		}

		mSessionToken.Set(token);
		mPlayerId.Set(playerId);
		mIsAuthenticated = true;

		Console.WriteLine("[ServerSave] Authenticated as player {}", playerId);

		// Load player data
		return Load();
	}

	/// Simple JSON string extraction (matches JsonHelper.GetString pattern).
	private static bool GetJsonString(StringView json, StringView key, String outValue)
	{
		let searchKey = scope String();
		searchKey.AppendF("\"{}\"", key);

		int keyPos = json.IndexOf(searchKey);
		if (keyPos < 0) return false;

		int pos = keyPos + searchKey.Length;
		while (pos < json.Length && (json[pos] == ' ' || json[pos] == ':'))
			pos++;

		if (pos >= json.Length) return false;

		if (json[pos] == '"')
		{
			pos++;
			let start = pos;
			while (pos < json.Length && json[pos] != '"')
			{
				if (json[pos] == '\\') pos++;
				pos++;
			}
			outValue.Append(json[start..<pos]);
			return true;
		}

		let start = pos;
		while (pos < json.Length && json[pos] != ',' && json[pos] != '}' && json[pos] != ' ')
			pos++;
		outValue.Append(json[start..<pos]);
		return true;
	}

	private static void SerializeToXml(PlayerSaveData data, String outXml)
	{
		let writer = XmlSerializer.CreateWriter();
		defer delete writer;
		var dataRef = data;
		writer.Object("PlayerData", ref dataRef);
		writer.GetOutput(outXml);
	}

	private static PlayerSaveData DeserializeFromXml(StringView xml)
	{
		let doc = scope XmlDocument();
		if (doc.Parse(xml) != .Ok)
			return null;

		let reader = XmlSerializer.CreateReader(doc);
		defer delete reader;

		PlayerSaveData data = null;
		reader.Object("PlayerData", ref data);
		return data;
	}
}
