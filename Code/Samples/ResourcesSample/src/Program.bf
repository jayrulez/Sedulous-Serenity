using System;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.OpenDDL;
using Sedulous.Resources;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;

namespace ResourcesSample;

/// A sample resource representing a player's save data.
class PlayerSaveResource : Resource
{
	public String PlayerName = new .() ~ delete _;
	public int32 Level;
	public int32 Experience;
	public float Health;
	public float MaxHealth;
	public Vector3 Position;
	public int32 Gold;

	public override int32 SerializationVersion => 1;

	protected override SerializationResult OnSerialize(Serializer s)
	{
		s.String("player_name", PlayerName);
		s.Int32("level", ref Level);
		s.Int32("experience", ref Experience);
		s.Float("health", ref Health);
		s.Float("max_health", ref MaxHealth);
		s.Float("position_x", ref Position.X);
		s.Float("position_y", ref Position.Y);
		s.Float("position_z", ref Position.Z);
		s.Int32("gold", ref Gold);
		return .Ok;
	}

	public void Print()
	{
		Console.WriteLine("=== Player Save Data ===");
		Console.WriteLine($"  ID: {Id}");
		Console.WriteLine($"  Name: {Name}");
		Console.WriteLine($"  Player: {PlayerName}");
		Console.WriteLine($"  Level: {Level}");
		Console.WriteLine($"  Experience: {Experience}");
		Console.WriteLine($"  Health: {Health}/{MaxHealth}");
		Console.WriteLine($"  Position: ({Position.X}, {Position.Y}, {Position.Z})");
		Console.WriteLine($"  Gold: {Gold}");
		Console.WriteLine("========================");
	}
}

class Program
{
	public static int Main(String[] args)
	{
		Console.WriteLine("Sedulous Resources Sample");
		Console.WriteLine("-------------------------\n");

		let savePath = scope String();
		Path.GetTempPath(savePath);
		savePath.Append("player_save.oddl");

		// Step 1: Create a resource with data
		Console.WriteLine("Step 1: Creating player save resource...\n");

		let originalSave = scope PlayerSaveResource();
		originalSave.Name.Set("PlayerSave_001");
		originalSave.PlayerName.Set("Hero");
		originalSave.Level = 25;
		originalSave.Experience = 15000;
		originalSave.Health = 85.5f;
		originalSave.MaxHealth = 100.0f;
		originalSave.Position = .(123.5f, 0.0f, -456.7f);
		originalSave.Gold = 9999;

		Console.WriteLine("Original resource:");
		originalSave.Print();
		Console.WriteLine();

		// Step 2: Save to disk
		Console.WriteLine($"Step 2: Saving to {savePath}...\n");

		if (!SaveResource(originalSave, savePath))
		{
			Console.WriteLine("ERROR: Failed to save resource!");
			return 1;
		}

		// Show the file contents
		Console.WriteLine("File contents (OpenDDL format):");
		Console.WriteLine("-------------------------------");
		let fileContent = scope String();
		if (File.ReadAllText(savePath, fileContent) == .Ok)
		{
			Console.WriteLine(fileContent);
		}
		Console.WriteLine("-------------------------------\n");

		// Step 3: Load from disk
		Console.WriteLine("Step 3: Loading from disk...\n");

		let loadedSave = scope PlayerSaveResource();
		if (!LoadResource(loadedSave, savePath))
		{
			Console.WriteLine("ERROR: Failed to load resource!");
			return 1;
		}

		Console.WriteLine("Loaded resource:");
		loadedSave.Print();
		Console.WriteLine();

		// Step 4: Verify data matches
		Console.WriteLine("Step 4: Verifying data...\n");

		bool allMatch = true;
		allMatch &= VerifyMatch("Name", originalSave.Name, loadedSave.Name);
		allMatch &= VerifyMatch("PlayerName", originalSave.PlayerName, loadedSave.PlayerName);
		allMatch &= VerifyMatch("Level", originalSave.Level, loadedSave.Level);
		allMatch &= VerifyMatch("Experience", originalSave.Experience, loadedSave.Experience);
		allMatch &= VerifyMatchFloat("Health", originalSave.Health, loadedSave.Health);
		allMatch &= VerifyMatchFloat("MaxHealth", originalSave.MaxHealth, loadedSave.MaxHealth);
		allMatch &= VerifyMatchFloat("Position.X", originalSave.Position.X, loadedSave.Position.X);
		allMatch &= VerifyMatchFloat("Position.Y", originalSave.Position.Y, loadedSave.Position.Y);
		allMatch &= VerifyMatchFloat("Position.Z", originalSave.Position.Z, loadedSave.Position.Z);
		allMatch &= VerifyMatch("Gold", originalSave.Gold, loadedSave.Gold);

		Console.WriteLine();

		if (allMatch)
		{
			Console.WriteLine("SUCCESS: All data verified correctly!");
		}
		else
		{
			Console.WriteLine("FAILURE: Some data did not match!");
			return 1;
		}

		// Cleanup
		if (File.Exists(savePath))
			File.Delete(savePath);

		Console.WriteLine("\nSample completed successfully.");
		return 0;
	}

	static bool SaveResource(Resource resource, StringView path)
	{
		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		if (resource.Serialize(writer) != .Ok)
			return false;

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output) == .Ok;
	}

	static bool LoadResource(Resource resource, StringView path)
	{
		let content = scope String();
		if (File.ReadAllText(path, content) != .Ok)
			return false;

		let doc = scope DataDescription();
		if (doc.ParseText(content) != .Ok)
			return false;

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		return resource.Serialize(reader) == .Ok;
	}

	static bool VerifyMatch<T>(StringView name, T original, T loaded)
	{
		if (original == loaded)
		{
			Console.WriteLine($"  [OK] {name}");
			return true;
		}
		else
		{
			Console.WriteLine($"  [FAIL] {name}: expected '{original}', got '{loaded}'");
			return false;
		}
	}

	static bool VerifyMatchFloat(StringView name, float original, float loaded)
	{
		if (MathUtil.Approximately(original, loaded))
		{
			Console.WriteLine($"  [OK] {name}");
			return true;
		}
		else
		{
			Console.WriteLine($"  [FAIL] {name}: expected '{original}', got '{loaded}'");
			return false;
		}
	}
}
