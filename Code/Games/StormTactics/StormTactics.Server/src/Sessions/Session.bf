namespace StormTactics.Server;

using System;

/// Represents an authenticated user session.
class Session
{
	public String mToken = new .() ~ delete _;
	public String mPlayerId = new .() ~ delete _;
	public String mUsername = new .() ~ delete _;
	public int64 mCreatedAt;
	public int64 mLastActivity;
}
