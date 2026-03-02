namespace Sedulous.Tools.SceneEditor;

using System;
using System.Collections;
using Sedulous.Tools.AppFramework;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.GUI;
using Sedulous.Render;
using Sedulous.Engine.Core;
using Sedulous.Engine.Scenes;
using Sedulous.Engine.Render;
using Sedulous.Tools.Core;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope SceneEditorApp();
		return app.Run();
	}
}
