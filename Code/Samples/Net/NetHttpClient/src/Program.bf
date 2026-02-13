namespace NetHttpClient;

using System;
using System.Threading;
using Sedulous.Net;
using Sedulous.Net.HTTP;

/// HTTP client/server demo.
/// Starts a local HttpServer with routes, then makes requests using HttpClient.
class Program
{
	public static int Main(String[] args)
	{
		Console.WriteLine("=== HTTP Client/Server Demo ===\n");

		// Create and configure server
		let server = scope HttpServer();

		server.Get("/", new (req, resp) => {
			resp.StatusCode = .OK;
			resp.ReasonPhrase.Set("OK");
			resp.SetBody("Welcome to the Sedulous HTTP Server!");
			resp.Headers.SetContentType("text/plain");
		});

		server.Get("/api/hello", new (req, resp) => {
			resp.StatusCode = .OK;
			resp.ReasonPhrase.Set("OK");
			resp.SetJsonBody("{\"message\": \"Hello from API!\"}");
		});

		server.Post("/api/echo", new (req, resp) => {
			resp.StatusCode = .OK;
			resp.ReasonPhrase.Set("OK");
			// Echo back the request body
			if (req.Body.Count > 0)
				resp.SetBody(Span<uint8>(req.Body.Ptr, req.Body.Count));
			else
				resp.SetBody("(empty body)");
			let ct = scope String();
			req.Headers.GetContentType(ct);
			if (!ct.IsEmpty)
				resp.Headers.SetContentType(ct);
		});

		server.Get("/api/status", new (req, resp) => {
			resp.StatusCode = .OK;
			resp.ReasonPhrase.Set("OK");
			resp.SetJsonBody("{\"status\": \"running\", \"uptime\": \"0s\"}");
		});

		if (server.Start(.(IPAddress(127, 0, 0, 1), 9200)) case .Err(let err))
		{
			let desc = scope String();
			err.GetDescription(desc);
			Console.WriteLine("Server start failed: {}", desc);
			return 1;
		}

		Console.WriteLine("Server running on http://127.0.0.1:9200\n");

		// Start server processing thread
		var serverDone = false;
		let serverThread = scope Thread(new () => {
			while (!serverDone)
			{
				server.Update();
				Thread.Sleep(5);
			}
		});
		serverThread.Start(false);

		// Give server time to start
		Thread.Sleep(100);

		// Make requests
		let client = scope HttpClient();
		client.TimeoutMs = 5000;

		// GET /
		Console.WriteLine("--- GET / ---");
		switch (client.Get("127.0.0.1", 9200, "/"))
		{
		case .Ok(let resp):
			let body = scope String();
			resp.GetBodyString(body);
			Console.WriteLine("Status: {}", (int32)resp.StatusCode);
			Console.WriteLine("Body: {}\n", body);
			delete resp;
		case .Err(let e1):
			let desc = scope String();
			e1.GetDescription(desc);
			Console.WriteLine("Error: {}\n", desc);
		}

		// GET /api/hello
		Console.WriteLine("--- GET /api/hello ---");
		switch (client.Get("127.0.0.1", 9200, "/api/hello"))
		{
		case .Ok(let resp):
			let body = scope String();
			resp.GetBodyString(body);
			Console.WriteLine("Status: {}", (int32)resp.StatusCode);
			Console.WriteLine("Body: {}\n", body);
			delete resp;
		case .Err(let e2):
			let desc = scope String();
			e2.GetDescription(desc);
			Console.WriteLine("Error: {}\n", desc);
		}

		// POST /api/echo
		Console.WriteLine("--- POST /api/echo ---");
		switch (client.Post("127.0.0.1", 9200, "/api/echo", "Hello from client!", "text/plain"))
		{
		case .Ok(let resp):
			let body = scope String();
			resp.GetBodyString(body);
			Console.WriteLine("Status: {}", (int32)resp.StatusCode);
			Console.WriteLine("Body: {}\n", body);
			delete resp;
		case .Err(let e3):
			let desc = scope String();
			e3.GetDescription(desc);
			Console.WriteLine("Error: {}\n", desc);
		}

		// GET nonexistent path
		Console.WriteLine("--- GET /api/missing ---");
		switch (client.Get("127.0.0.1", 9200, "/api/missing"))
		{
		case .Ok(let resp):
			let body = scope String();
			resp.GetBodyString(body);
			Console.WriteLine("Status: {} (expected 404)", (int32)resp.StatusCode);
			Console.WriteLine("Body: {}\n", body);
			delete resp;
		case .Err(let e4):
			let desc = scope String();
			e4.GetDescription(desc);
			Console.WriteLine("Error: {}\n", desc);
		}

		// Cleanup
		serverDone = true;
		serverThread.Join();
		server.Stop();

		Console.WriteLine("=== Done ===");
		return 0;
	}
}
