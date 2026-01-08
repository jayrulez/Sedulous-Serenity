using System;
using System.Collections;
using System.IO;
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
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
			//Environment.GetExecutableFilePath(wavPath);
			let lastSlash = Math.Max(wavPath.LastIndexOf('/'), wavPath.LastIndexOf('\\'));
			if (lastSlash >= 0)
				wavPath.RemoveToEnd(lastSlash + 1);
			wavPath.Append("come_get_it.wav");
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

		// Wait for playback
		float elapsed = 0;
		while (source.State == .Playing && elapsed < 5.0f)
		{
			audioSystem.Update();
			System.Threading.Thread.Sleep(100);
			elapsed += 0.1f;

			if (((int)(elapsed * 10) % 10) == 0)
				Console.WriteLine(scope $"  Playing... {elapsed:F1}s");
		}

		Console.WriteLine(scope $"Final source state: {source.State}");
		Console.WriteLine();

		// Test pitch control
		Console.WriteLine("Testing pitch control (1.5x speed)...");
		source.Pitch = 1.5f;
		source.Play(clip);

		elapsed = 0;
		while (source.State == .Playing && elapsed < 3.0f)
		{
			audioSystem.Update();
			System.Threading.Thread.Sleep(100);
			elapsed += 0.1f;
		}
		Console.WriteLine("Pitch test complete.");
		Console.WriteLine();

		// Test master volume
		Console.WriteLine("Testing master volume (50%)...");
		source.Pitch = 1.0f;
		audioSystem.MasterVolume = 0.5f;
		source.Play(clip);

		elapsed = 0;
		while (source.State == .Playing && elapsed < 2.0f)
		{
			audioSystem.Update();
			System.Threading.Thread.Sleep(100);
			elapsed += 0.1f;
		}
		source.Stop();
		audioSystem.MasterVolume = 1.0f;
		Console.WriteLine("Master volume test complete.");
		Console.WriteLine();

		// Test PauseAll/ResumeAll
		Console.WriteLine("Testing PauseAll/ResumeAll...");
		source.Play(clip);
		System.Threading.Thread.Sleep(500);
		Console.WriteLine("  Pausing all audio...");
		audioSystem.PauseAll();
		System.Threading.Thread.Sleep(1000);
		Console.WriteLine("  Resuming all audio...");
		audioSystem.ResumeAll();
		System.Threading.Thread.Sleep(1000);
		source.Stop();
		Console.WriteLine("PauseAll/ResumeAll test complete.");
		Console.WriteLine();

		// Test PlayOneShot
		Console.WriteLine("Testing PlayOneShot...");
		audioSystem.PlayOneShot(clip, 1.0f);

		// Need to call Update() for one-shot cleanup
		elapsed = 0;
		while (elapsed < 2.0f)
		{
			audioSystem.Update();
			System.Threading.Thread.Sleep(100);
			elapsed += 0.1f;
		}
		Console.WriteLine("PlayOneShot test complete.");
		Console.WriteLine();

		// Test PlayOneShot3D
		Console.WriteLine("Testing PlayOneShot3D...");
		// Set listener at origin looking down negative Z
		audioSystem.Listener.Position = Vector3.Zero;
		audioSystem.Listener.Forward = .(0, 0, -1);
		audioSystem.Listener.Up = .(0, 1, 0);

		// Play sound 10 units in front
		audioSystem.PlayOneShot3D(clip, .(0, 0, -10), 1.0f);

		elapsed = 0;
		while (elapsed < 2.0f)
		{
			audioSystem.Update();
			System.Threading.Thread.Sleep(100);
			elapsed += 0.1f;
		}
		Console.WriteLine("PlayOneShot3D test complete.");
		Console.WriteLine();

		// Test 3D stereo panning - moving source
		Console.WriteLine("Testing 3D stereo panning (moving source)...");
		Console.WriteLine("  Sound will pan from left to right");

		let movingSource = audioSystem.CreateSource();
		movingSource.Loop = true;
		movingSource.Position = .(-10, 0, 0);  // Start on left
		movingSource.Play(clip);

		// Move source from left to right over 3 seconds
		elapsed = 0;
		while (elapsed < 3.0f)
		{
			// Pan from -10 to +10 over 3 seconds
			let xPos = -10.0f + (elapsed / 3.0f) * 20.0f;
			movingSource.Position = .(xPos, 0, 0);

			audioSystem.Update();
			System.Threading.Thread.Sleep(50);
			elapsed += 0.05f;
		}
		movingSource.Stop();
		audioSystem.DestroySource(movingSource);
		Console.WriteLine("3D stereo panning test complete.");
		Console.WriteLine();

		// Test audio streaming (if a music file exists)
		Console.WriteLine("Testing audio streaming...");
		String musicPath = scope .();
		musicPath.Set(wavPath);  // Try to use same wav file for streaming test

		switch (audioSystem.OpenStream(musicPath))
		{
		case .Ok(let musicStream):
			Console.WriteLine(scope $"  Stream opened: {musicStream.Duration:F2}s, {musicStream.SampleRate}Hz, {musicStream.Channels}ch");
			musicStream.Volume = 0.5f;
			musicStream.Play();

			// Play for 2 seconds
			elapsed = 0;
			while (musicStream.State == .Playing && elapsed < 2.0f)
			{
				audioSystem.Update();
				System.Threading.Thread.Sleep(100);
				elapsed += 0.1f;
			}

			// Test seek
			Console.WriteLine("  Testing seek to 0.5s...");
			musicStream.Seek(0.5f);

			elapsed = 0;
			while (musicStream.State == .Playing && elapsed < 1.0f)
			{
				audioSystem.Update();
				System.Threading.Thread.Sleep(100);
				elapsed += 0.1f;
			}

			musicStream.Stop();
			Console.WriteLine("Audio streaming test complete.");
		case .Err:
			Console.WriteLine("  Could not open stream (file may not exist)");
			Console.WriteLine("  Streaming test skipped.");
		}
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
