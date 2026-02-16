namespace StormTactics.Server;

using System;
using System.Collections;

/// Manages authenticated sessions (in-memory only).
class SessionManager
{
	private Dictionary<String, Session> mSessions = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	private int32 mTimeoutSeconds = 3600;

	public void Initialize(int32 timeoutSeconds)
	{
		mTimeoutSeconds = timeoutSeconds;
	}

	/// Create a new session for an authenticated player.
	public Session CreateSession(StringView playerId, StringView username)
	{
		let session = new Session();

		let token = Guid.Create();
		token.ToString(session.mToken);

		session.mPlayerId.Set(playerId);
		session.mUsername.Set(username);
		session.mCreatedAt = GetTimestamp();
		session.mLastActivity = session.mCreatedAt;

		let key = new String(session.mToken);
		mSessions[key] = session;

		Console.WriteLine("[Session] Created for {} (token: {}...)", username, session.mToken.Substring(0, 8));
		return session;
	}

	/// Validate a session token. Returns the session if valid, null otherwise.
	/// Updates last activity on success.
	public Session ValidateSession(StringView token)
	{
		let key = scope String(token);
		if (mSessions.TryGetValue(key, let session))
		{
			let now = GetTimestamp();
			if (now - session.mLastActivity > mTimeoutSeconds)
			{
				// Expired
				Console.WriteLine("[Session] Expired for {}", session.mUsername);
				let ownedKey = new String();
				ownedKey.Set(token);
				RemoveSession(key);
				return null;
			}
			session.mLastActivity = now;
			return session;
		}
		return null;
	}

	/// Remove a session (logout).
	public void InvalidateSession(StringView token)
	{
		let key = scope String(token);
		RemoveSession(key);
	}

	/// Remove expired sessions.
	public void CleanExpiredSessions()
	{
		let now = GetTimestamp();
		let toRemove = scope List<String>();

		for (let pair in mSessions)
		{
			if (now - pair.value.mLastActivity > mTimeoutSeconds)
				toRemove.Add(pair.key);
		}

		for (let key in toRemove)
			RemoveSession(key);
	}

	private void RemoveSession(StringView key)
	{
		let lookupKey = scope String(key);
		if (mSessions.TryGetValue(lookupKey, let session))
		{
			// Need to get the actual owned key from the dictionary
			for (let pair in mSessions)
			{
				if (pair.key == lookupKey)
				{
					let ownedKey = pair.key;
					mSessions.Remove(lookupKey);
					delete ownedKey;
					delete session;
					break;
				}
			}
		}
	}

	private static int64 GetTimestamp()
	{
		return DateTime.UtcNow.ToFileTime() / 10000000 - 11644473600;
	}
}
