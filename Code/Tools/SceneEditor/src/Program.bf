namespace SceneEditor;

using System;
using System.Collections;
using Sedulous.AppFramework;
using Sedulous.Foundation.Mathematics;
using Sedulous.RHI;
using Sedulous.GUI;
using Sedulous.Render;
using Sedulous.Engine.Core;
using Sedulous.Engine.Scenes;
using Sedulous.Engine.Render;
using Tools.Common;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope SceneEditorApp();
		return app.Run();
	}
}
