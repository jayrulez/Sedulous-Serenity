namespace Sedulous.Editor.Runner;

using System;
using Sedulous.Editor.App;
using Sedulous.Editor.Scenes;
using Sedulous.Core.Logging.Abstractions;
using Sedulous.Core.Logging.Console;

class Program
{
	public static int Main(String[] args)
	{
		// Set up console logging
		let consoleLogger = scope ConsoleLogger(.Debug, "Editor");

		// Parse command line args for log level
		for (let arg in args)
		{
			if (arg == "--verbose" || arg == "-v")
				consoleLogger.MimimumLogLevel = .Trace;
			else if (arg == "--quiet" || arg == "-q")
				consoleLogger.MimimumLogLevel = .Warning;
		}

		// Create editor application
		let config = EditorConfig();
		let app = scope EditorApplication(config);

		// Set console logger as inner logger (messages will be forwarded to it)
		app.SetInnerLogger(consoleLogger);

		// Register editor modules (plugin system)
		app.RegisterModule(new SceneEditorModule());

		// Run the editor
		return app.Run();
	}
}
