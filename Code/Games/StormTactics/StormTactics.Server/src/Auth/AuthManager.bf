namespace StormTactics.Server;

using System;
using System.IO;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Serialization.Xml;
using Sedulous.Xml;

/// Manages user accounts: registration, login, and persistence.
class AuthManager
{
	private Dictionary<String, AccountData> mAccounts = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	private String mAccountsPath = new .() ~ delete _;

	/// Initialize with the path to accounts.xml.
	public void Initialize(StringView dataDir)
	{
		mAccountsPath.Set(dataDir);
		Path.InternalCombine(mAccountsPath, mAccountsPath, "accounts.xml");
		LoadAccounts();
	}

	/// Register a new account. Returns the account on success.
	public Result<AccountData> Register(StringView username, StringView password)
	{
		if (username.Length < 1 || password.Length < 1)
			return .Err;

		// Check for existing
		let key = scope String(username);
		if (mAccounts.ContainsKey(key))
			return .Err;

		// Create account
		let account = new AccountData();
		account.mUsername.Set(username);
		PasswordHasher.GenerateSalt(account.mSalt);
		PasswordHasher.Hash(password, account.mSalt, account.mPasswordHash);

		let playerId = Guid.Create();
		playerId.ToString(account.mPlayerId);

		account.mCreatedAt = DateTime.UtcNow.ToFileTime() / 10000000 - 11644473600;

		let ownedKey = new String(username);
		mAccounts[ownedKey] = account;

		SaveAccounts();

		Console.WriteLine("[Auth] Registered: {} -> player {}", username, account.mPlayerId);
		return .Ok(account);
	}

	/// Verify login credentials. Returns the account on success.
	public Result<AccountData> Login(StringView username, StringView password)
	{
		let key = scope String(username);
		if (mAccounts.TryGetValue(key, let account))
		{
			if (PasswordHasher.Verify(password, account.mSalt, account.mPasswordHash))
			{
				Console.WriteLine("[Auth] Login success: {}", username);
				return .Ok(account);
			}
		}
		return .Err;
	}

	/// Check if a username is already registered.
	public bool HasAccount(StringView username)
	{
		let key = scope String(username);
		return mAccounts.ContainsKey(key);
	}

	/// Load accounts from XML file.
	private void LoadAccounts()
	{
		let xmlText = scope String();
		if (File.ReadAllText(mAccountsPath, xmlText) case .Err)
		{
			Console.WriteLine("[Auth] No accounts file — starting fresh");
			return;
		}

		let doc = scope XmlDocument();
		if (doc.Parse(xmlText) != .Ok)
		{
			Console.WriteLine("[Auth] ERROR: Failed to parse accounts.xml");
			return;
		}

		let reader = XmlSerializer.CreateReader(doc);
		defer delete reader;

		let accountList = scope List<AccountData>();
		reader.ObjectList("Accounts", accountList);

		for (let account in accountList)
		{
			let key = new String(account.mUsername);
			mAccounts[key] = account;
		}

		// The scope list will be deleted but the AccountData objects are now owned by the dictionary
		accountList.Clear(); // Don't let scope cleanup delete the items

		Console.WriteLine("[Auth] Loaded {} accounts", mAccounts.Count);
	}

	/// Save all accounts to XML file.
	private void SaveAccounts()
	{
		let writer = XmlSerializer.CreateWriter();
		defer delete writer;

		let accountList = scope List<AccountData>();
		for (let account in mAccounts.Values)
			accountList.Add(account);

		writer.ObjectList("Accounts", accountList);

		let output = scope String();
		writer.GetOutput(output);

		// Ensure directory exists
		let dir = scope String();
		Path.GetDirectoryPath(mAccountsPath, dir);
		if (!dir.IsEmpty)
			Directory.CreateDirectory(dir);

		if (File.WriteAllText(mAccountsPath, output) case .Err)
			Console.WriteLine("[Auth] ERROR: Failed to write accounts.xml");
	}
}
