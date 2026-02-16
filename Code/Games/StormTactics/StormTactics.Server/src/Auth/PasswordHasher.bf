namespace StormTactics.Server;

using System;
using Sedulous.Net;

/// Password hashing using salted double-SHA1.
static class PasswordHasher
{
	/// Hash a password with a salt. Output is a 40-character hex string.
	public static void Hash(StringView password, StringView salt, String outHash)
	{
		// Concatenate: salt + password
		let combined = scope String();
		combined.Append(salt);
		combined.Append(password);

		// First SHA-1 pass
		let hash1 = SHA1.Hash(combined);
		let hex1 = scope String();
		hash1.ToString(hex1);

		// Second SHA-1 pass
		let hash2 = SHA1.Hash(hex1);
		hash2.ToString(outHash);
	}

	/// Generate a random 32-character hex salt.
	public static void GenerateSalt(String outSalt)
	{
		let rng = scope Random();
		for (int i = 0; i < 16; i++)
			outSalt.AppendF("{:x2}", (uint8)rng.Next(256));
	}

	/// Verify a password against a stored hash and salt.
	public static bool Verify(StringView password, StringView salt, StringView expectedHash)
	{
		let computed = scope String();
		Hash(password, salt, computed);
		return StringView.Compare(computed, expectedHash, false) == 0;
	}
}
