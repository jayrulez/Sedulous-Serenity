using System;
using System.Collections;
using System.IO;
using Sedulous.Framework.Audio;
using Sedulous.Framework.Audio.SDL3;
using Sedulous.Mathematics;
using SDL3;

namespace AudioSample;

class Program
{
	public static int Main(String[] args)
	{
		Console.WriteLine("=== Audio Sample ===");
		Console.WriteLine();

		// Create audio system
		Console.WriteLine("Creating audio system...");
		let audioSystem = new SDL3AudioSystem();
		defer delete audioSystem;

		if (!audioSystem.IsInitialized)
		{
			Console.WriteLine("ERROR: Audio system failed to initialize!");
			return 1;
		}
		Console.WriteLine("Audio system initialized successfully.");

		// Try to load WAV file from disk
		String wavPath = scope .();
		if (args.Count > 0)
		{
			wavPath.Set(args[0]);
		}
		else
		{
			// Default path - look for test.wav in the executable directory
			Environment.GetExecutableFilePath(wavPath);
			let lastSlash = Math.Max(wavPath.LastIndexOf('/'), wavPath.LastIndexOf('\\'));
			if (lastSlash >= 0)
				wavPath.RemoveToEnd(lastSlash + 1);
			wavPath.Append("test.wav");
		}

		Console.WriteLine(scope $"Loading WAV file: {wavPath}");

		// Read WAV file
		List<uint8> wavData = new .();
		defer delete wavData;

		if (File.Exists(wavPath))
		{
			let result = File.ReadAll(wavPath, wavData);
			if (result case .Err)
			{
				Console.WriteLine(scope $"ERROR: Failed to read WAV file: {wavPath}");
				return 1;
			}
			Console.WriteLine(scope $"Read {wavData.Count} bytes from WAV file.");
		}
		else
		{
			Console.WriteLine(scope $"WAV file not found: {wavPath}");
			Console.WriteLine("Generating sine wave instead...");

			GenerateSineWave(wavData, 440.0f, 1.0f, 44100);
			Console.WriteLine(scope $"Generated {wavData.Count} bytes of sine wave data.");
		}

		// Load clip
		Console.WriteLine("Loading audio clip...");
		IAudioClip clip = null;

		switch (audioSystem.LoadClip(Span<uint8>(wavData.Ptr, wavData.Count)))
		{
		case .Ok(let c):
			clip = c;
			Console.WriteLine(scope $"Clip loaded successfully!");
			Console.WriteLine(scope $"  Duration: {clip.Duration:F2} seconds");
			Console.WriteLine(scope $"  Sample rate: {clip.SampleRate} Hz");
			Console.WriteLine(scope $"  Channels: {clip.Channels}");
		case .Err:
			Console.WriteLine("ERROR: Failed to load audio clip!");
			let sdlError = SDL_GetError();
			if (sdlError != null && sdlError[0] != 0)
				Console.WriteLine(scope $"  SDL Error: {StringView(sdlError)}");
			return 1;
		}
		defer delete clip;

		// Create audio source
		Console.WriteLine("Creating audio source...");
		let source = audioSystem.CreateSource();
		if (source == null)
		{
			Console.WriteLine("ERROR: Failed to create audio source!");
			return 1;
		}
		Console.WriteLine("Audio source created.");

		// Play the sound
		Console.WriteLine();
		Console.WriteLine("Playing audio... (press Enter to stop)");
		source.Volume = 1.0f;
		source.Play(clip);

		Console.WriteLine(scope $"Source state after Play(): {source.State}");

		// Wait for playback or user input
		float elapsed = 0;
		while (source.State == .Playing && elapsed < 10.0f)
		{
			audioSystem.Update();
			System.Threading.Thread.Sleep(100);
			elapsed += 0.1f;

			if (((int)(elapsed * 10) % 10) == 0)
				Console.WriteLine(scope $"  Playing... {elapsed:F1}s");
		}

		Console.WriteLine(scope $"Final source state: {source.State}");
		Console.WriteLine();

		// Test PlayOneShot
		Console.WriteLine("Testing PlayOneShot...");
		audioSystem.PlayOneShot(clip, 1.0f);
		System.Threading.Thread.Sleep(2000);

		Console.WriteLine();
		Console.WriteLine("=== Audio Sample Complete ===");

		return 0;
	}

	/// Generates a WAV file in memory containing a sine wave tone.
	private static void GenerateSineWave(List<uint8> wav, float frequency, float duration, int32 sampleRate)
	{
		let numSamples = (int32)(sampleRate * duration);
		let numChannels = (int16)2;  // Stereo
		let bitsPerSample = (int16)16;
		let bytesPerSample = bitsPerSample / 8;
		let dataSize = numSamples * numChannels * bytesPerSample;

		// RIFF header
		wav.AddRange(Span<uint8>((uint8*)"RIFF", 4));
		WriteInt32(wav, 36 + dataSize);  // File size - 8
		wav.AddRange(Span<uint8>((uint8*)"WAVE", 4));

		// fmt chunk
		wav.AddRange(Span<uint8>((uint8*)"fmt ", 4));
		WriteInt32(wav, 16);  // Chunk size
		WriteInt16(wav, 1);   // Audio format (1 = PCM)
		WriteInt16(wav, numChannels);
		WriteInt32(wav, sampleRate);
		WriteInt32(wav, sampleRate * numChannels * bytesPerSample);  // Byte rate
		WriteInt16(wav, (int16)(numChannels * bytesPerSample));      // Block align
		WriteInt16(wav, bitsPerSample);

		// data chunk
		wav.AddRange(Span<uint8>((uint8*)"data", 4));
		WriteInt32(wav, dataSize);

		// Generate sine wave samples
		let twoPiF = 2.0f * Math.PI_f * frequency;
		for (int32 i = 0; i < numSamples; i++)
		{
			let t = (float)i / (float)sampleRate;
			let sample = Math.Sin(twoPiF * t);

			// Apply a simple envelope to avoid clicks
			float envelope = 1.0f;
			let attackSamples = sampleRate / 100;  // 10ms attack
			let releaseSamples = sampleRate / 50;  // 20ms release
			if (i < attackSamples)
				envelope = (float)i / (float)attackSamples;
			else if (i > numSamples - releaseSamples)
				envelope = (float)(numSamples - i) / (float)releaseSamples;

			let value = (int16)(sample * envelope * 30000);
			// Write stereo (same value for both channels)
			WriteInt16(wav, value);
			WriteInt16(wav, value);
		}
	}

	private static void WriteInt16(List<uint8> buffer, int16 value)
	{
		buffer.Add((uint8)(value & 0xFF));
		buffer.Add((uint8)((value >> 8) & 0xFF));
	}

	private static void WriteInt32(List<uint8> buffer, int32 value)
	{
		buffer.Add((uint8)(value & 0xFF));
		buffer.Add((uint8)((value >> 8) & 0xFF));
		buffer.Add((uint8)((value >> 16) & 0xFF));
		buffer.Add((uint8)((value >> 24) & 0xFF));
	}
}
