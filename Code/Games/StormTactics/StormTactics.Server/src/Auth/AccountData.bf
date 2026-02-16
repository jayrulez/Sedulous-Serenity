namespace StormTactics.Server;

using System;
using Sedulous.Serialization;

/// Stores a single user account record.
class AccountData : ISerializable
{
	public String mUsername = new .() ~ delete _;
	public String mPasswordHash = new .() ~ delete _;
	public String mSalt = new .() ~ delete _;
	public String mPlayerId = new .() ~ delete _;
	public int64 mCreatedAt;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.String("Username", mUsername);
		s.String("PasswordHash", mPasswordHash);
		s.String("Salt", mSalt);
		s.String("PlayerId", mPlayerId);
		s.Int64("CreatedAt", ref mCreatedAt);
		return .Ok;
	}
}
