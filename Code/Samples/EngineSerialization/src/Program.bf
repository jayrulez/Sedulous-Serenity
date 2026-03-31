namespace EngineSerialization;

using System;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope EngineSerializationApp();
		return app.Run(.()
		{
			Title = "Framework Serialization Sample",
			Width = 1280, Height = 720,
			EnableDepth = true
		});
	}
}
