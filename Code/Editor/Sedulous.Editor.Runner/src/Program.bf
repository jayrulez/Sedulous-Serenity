namespace Sedulous.Editor.Runner;

using System;
using Sedulous.Editor.App;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Console;

class Program
{
	public static int Main(String[] args)
	{
		// Set up logging
		let logger = scope ConsoleLogger(.Debug, "Editor");
		EditorApplication.SetLogger(logger);

		// Parse command line args for log level
		for (let arg in args)
		{
			if (arg == "--verbose" || arg == "-v")
				logger.MimimumLogLevel = .Trace;
			else if (arg == "--quiet" || arg == "-q")
				logger.MimimumLogLevel = .Warning;
		}

		// Create and run editor
		let config = EditorConfig();
		let app = scope EditorApplication(config);
		return app.Run();
	}
}
