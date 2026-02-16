namespace StormTactics.Server;

using System;

/// Minimal flat JSON builder/parser for auth request/response bodies.
/// Only handles flat key-value objects with string, int, and bool values.
static class JsonHelper
{
	/// Build a JSON object string from key-value string pairs.
	/// Values are written as JSON strings (quoted).
	public static void BuildObject(String outJson, params Span<(StringView key, StringView value)> pairs)
	{
		outJson.Append('{');
		bool first = true;
		for (let pair in pairs)
		{
			if (!first) outJson.Append(',');
			first = false;
			outJson.Append('"');
			EscapeString(pair.key, outJson);
			outJson.Append("\":\"");
			EscapeString(pair.value, outJson);
			outJson.Append('"');
		}
		outJson.Append('}');
	}

	/// Build a JSON object with mixed value types.
	/// Use "true"/"false" for bools, numeric strings for numbers (written unquoted).
	public static void BuildObjectRaw(String outJson, params Span<(StringView key, StringView value, bool quoted)> fields)
	{
		outJson.Append('{');
		bool first = true;
		for (let field in fields)
		{
			if (!first) outJson.Append(',');
			first = false;
			outJson.Append('"');
			EscapeString(field.key, outJson);
			outJson.Append("\":");
			if (field.quoted)
			{
				outJson.Append('"');
				EscapeString(field.value, outJson);
				outJson.Append('"');
			}
			else
			{
				outJson.Append(field.value);
			}
		}
		outJson.Append('}');
	}

	/// Extract a string value by key from a flat JSON object.
	/// Returns true if found and extracted.
	public static bool GetString(StringView json, StringView key, String outValue)
	{
		// Find "key" pattern
		let searchKey = scope String();
		searchKey.Append('"');
		searchKey.Append(key);
		searchKey.Append('"');

		int keyPos = json.IndexOf(searchKey);
		if (keyPos < 0) return false;

		// Skip past key and colon
		int pos = keyPos + searchKey.Length;
		while (pos < json.Length && (json[pos] == ' ' || json[pos] == ':'))
			pos++;

		if (pos >= json.Length) return false;

		// Check if value is quoted string
		if (json[pos] == '"')
		{
			pos++;
			let start = pos;
			while (pos < json.Length && json[pos] != '"')
			{
				if (json[pos] == '\\') pos++; // skip escaped char
				pos++;
			}
			outValue.Append(json[start..<pos]);
			return true;
		}

		// Unquoted value (number, bool, null)
		let start = pos;
		while (pos < json.Length && json[pos] != ',' && json[pos] != '}' && json[pos] != ' ')
			pos++;
		outValue.Append(json[start..<pos]);
		return true;
	}

	/// Extract an int32 value by key.
	public static Result<int32> GetInt32(StringView json, StringView key)
	{
		let val = scope String();
		if (!GetString(json, key, val))
			return .Err;
		if (int32.Parse(val) case .Ok(let v))
			return .Ok(v);
		return .Err;
	}

	/// Extract a bool value by key.
	public static Result<bool> GetBool(StringView json, StringView key)
	{
		let val = scope String();
		if (!GetString(json, key, val))
			return .Err;
		return val == "true";
	}

	/// Build a simple error response JSON.
	public static void BuildError(String outJson, StringView error)
	{
		BuildObjectRaw(outJson,
			("success", "false", false),
			("error", error, true));
	}

	/// Build a simple success response JSON.
	public static void BuildSuccess(String outJson)
	{
		BuildObjectRaw(outJson,
			("success", "true", false));
	}

	private static void EscapeString(StringView str, String outStr)
	{
		for (let c in str.RawChars)
		{
			switch (c)
			{
			case '"': outStr.Append("\\\"");
			case '\\': outStr.Append("\\\\");
			case '\n': outStr.Append("\\n");
			case '\r': outStr.Append("\\r");
			case '\t': outStr.Append("\\t");
			default: outStr.Append(c);
			}
		}
	}
}
