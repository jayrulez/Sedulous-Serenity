namespace NetWebSocket;

using System;
using System.Threading;
using System.Collections;
using Sedulous.Net;
using Sedulous.Net.HTTP;

/// WebSocket echo demo.
/// Starts an HTTP server with WebSocket upgrade support, connects a client,
/// sends text/binary messages, and receives echoes.
class Program
{
	public static int Main(String[] args)
	{
		Console.WriteLine("=== WebSocket Echo Demo ===\n");

		let server = scope HttpServer();
		let wsConnections = scope List<WebSocketConnection>();
		defer { DeleteContainerAndItems!(wsConnections); }

		// Configure WebSocket upgrade handler
		server.OnWebSocketUpgrade = new [&](client, request) => {
			let ws = new WebSocketConnection();
			if (ws.AcceptUpgrade(client, request, true) case .Ok)
			{
				Console.WriteLine("[Server] WebSocket connection accepted");
				wsConnections.Add(ws);
				return true;
			}
			delete ws;
			return false;
		};

		// Also add a regular HTTP endpoint
		server.Get("/", new (req, resp) => {
			resp.StatusCode = .OK;
			resp.ReasonPhrase.Set("OK");
			resp.SetBody("WebSocket Echo Server - connect with ws://127.0.0.1:9300/");
		});

		if (server.Start(.(IPAddress(127, 0, 0, 1), 9300)) case .Err(let err))
		{
			let desc = scope String();
			err.GetDescription(desc);
			Console.WriteLine("Server start failed: {}", desc);
			return 1;
		}

		Console.WriteLine("Server running on ws://127.0.0.1:9300\n");

		// Server processing thread
		var serverDone = false;
		let serverThread = scope Thread(new [&]() => {
			while (!serverDone)
			{
				server.Update();

				// Echo back received messages
				for (let ws in wsConnections)
				{
					if (ws.State != .Open) continue;
					let msg = ws.Receive();
					if (msg != null)
					{
						switch (msg.OpCode)
						{
						case .Text:
							let text = scope String();
							msg.GetText(text);
							Console.WriteLine("[Server] Received text: \"{}\"", text);
							ws.SendText(text);
							Console.WriteLine("[Server] Echoed text back");
						case .Binary:
							Console.WriteLine("[Server] Received {} bytes binary", msg.Data.Count);
							ws.SendBinary(Span<uint8>(msg.Data.Ptr, msg.Data.Count));
							Console.WriteLine("[Server] Echoed binary back");
						default:
						}
						delete msg;
					}
				}

				Thread.Sleep(10);
			}
		});
		serverThread.Start(false);

		Thread.Sleep(100);

		// Connect WebSocket client
		let wsClient = scope WebSocketClient();
		Console.WriteLine("[Client] Connecting...");

		if (wsClient.Connect("127.0.0.1", 9300) case .Err(let connectErr))
		{
			let desc = scope String();
			connectErr.GetDescription(desc);
			Console.WriteLine("[Client] Connect failed: {}", desc);
			serverDone = true;
			serverThread.Join();
			server.Stop();
			return 1;
		}

		Console.WriteLine("[Client] Connected! State: {}\n", wsClient.State);

		// Send text messages
		StringView[?] messages = .("Hello WebSocket!", "Testing 1 2 3", "Beef networking is cool!");

		for (let msg in messages)
		{
			Console.WriteLine("[Client] Sending: \"{}\"", msg);
			wsClient.SendText(msg);
			Thread.Sleep(200);

			let reply = wsClient.Receive();
			if (reply != null)
			{
				let text = scope String();
				reply.GetText(text);
				Console.WriteLine("[Client] Got echo: \"{}\"\n", text);
				delete reply;
			}
			else
			{
				Console.WriteLine("[Client] No reply yet\n");
			}
		}

		// Send binary data
		Console.WriteLine("[Client] Sending 16 bytes of binary data");
		uint8[16] binData = default;
		for (int i = 0; i < 16; i++)
			binData[i] = (uint8)(i * 17);
		wsClient.SendBinary(Span<uint8>(&binData, 16));
		Thread.Sleep(200);

		let binReply = wsClient.Receive();
		if (binReply != null)
		{
			Console.WriteLine("[Client] Got {} bytes binary echo", binReply.Data.Count);
			delete binReply;
		}

		// Close
		Console.WriteLine("\n[Client] Closing connection...");
		wsClient.Close();
		Console.WriteLine("[Client] State: {}", wsClient.State);

		// Cleanup
		serverDone = true;
		serverThread.Join();
		server.Stop();

		Console.WriteLine("\n=== Done ===");
		return 0;
	}
}
