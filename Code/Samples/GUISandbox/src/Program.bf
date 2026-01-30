namespace GUISandbox;

using System;
using Sedulous.RHI;
using SampleFramework;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope GUISandboxApp();
		return app.Run();
	}
}
