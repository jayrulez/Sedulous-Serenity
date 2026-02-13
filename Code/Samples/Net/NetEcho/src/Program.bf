namespace NetEcho;

using System;
using System.Threading;
using Sedulous.Net;

/// TCP echo server + client demo.
/// Demonstrates TcpListener, TcpClient, non-blocking Accept, SendAll/Recv.
class Program
{
	public static int Main(String[] args)
	{
		Console.WriteLine("=== TCP Echo Server Demo ===\n");

		// Start the echo server
		let listener = scope TcpListener();
		if (listener.Start(.(IPAddress(127, 0, 0, 1), 9100)) case .Err(let err))
		{
			let desc = scope String();
			err.GetDescription(desc);
			Console.WriteLine("Failed to start server: {}", desc);
			return 1;
		}

		Console.WriteLine("Server listening on 127.0.0.1:9100");

		// Connect a client
		let client = scope TcpClient();
		if (client.Connect("127.0.0.1", 9100) case .Err(let connectErr))
		{
			let desc = scope String();
			connectErr.GetDescription(desc);
			Console.WriteLine("Failed to connect: {}", desc);
			return 1;
		}

		Console.WriteLine("Client connected to server");
		Thread.Sleep(50);

		// Accept the client on the server side
		TcpClient serverClient = null;
		defer { delete serverClient; }

		switch (listener.Accept())
		{
		case .Ok(let sc):
			serverClient = sc;
			Console.WriteLine("Server accepted connection");
		case .Err(let acceptErr):
			let desc = scope String();
			acceptErr.GetDescription(desc);
			Console.WriteLine("Accept failed: {}", desc);
			return 1;
		}

		// Send messages and echo them back
		StringView[?] messages = .("Hello, TCP!", "This is a test message.", "Echo server is working!", "Goodbye!");

		for (let msg in messages)
		{
			// Client sends
			if (client.SendAll(Span<uint8>((uint8*)msg.Ptr, msg.Length)) case .Err)
			{
				Console.WriteLine("Send failed");
				continue;
			}
			Console.WriteLine("Client sent: \"{}\"", msg);

			Thread.Sleep(50);

			// Server receives
			uint8[256] recvBuf = default;
			switch (serverClient.Recv(Span<uint8>(&recvBuf, 256)))
			{
			case .Ok(let received):
				let recvStr = scope String();
				recvStr.Append((char8*)&recvBuf, received);
				Console.WriteLine("Server received: \"{}\"", recvStr);

				// Echo back
				serverClient.SendAll(Span<uint8>(&recvBuf, received));
			case .Err:
				Console.WriteLine("Recv failed");
			}

			Thread.Sleep(50);

			// Client receives echo
			uint8[256] echoBuf = default;
			switch (client.Recv(Span<uint8>(&echoBuf, 256)))
			{
			case .Ok(let received):
				let echoStr = scope String();
				echoStr.Append((char8*)&echoBuf, received);
				Console.WriteLine("Client got echo: \"{}\"\n", echoStr);
			case .Err:
				Console.WriteLine("Echo recv failed");
			}
		}

		// Cleanup
		client.Close();
		serverClient.Close();
		listener.Stop();

		Console.WriteLine("=== Done ===");
		return 0;
	}
}
