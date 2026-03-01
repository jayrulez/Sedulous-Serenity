namespace Sedulous.Engine.UI;

using System;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Transient serialization data for WorldUIComponent.
/// Only exists during save/load — not stored at runtime.
struct WorldUIComponentData
{
	[Property]
	public bool Enabled;
	[Property]
	public uint32 PixelWidth;
	[Property]
	public uint32 PixelHeight;
	[Property]
	public float PanelWidth;
	[Property]
	public float PanelHeight;
	[Property]
	public bool IsInteractive;

	public int32 SerializationVersion => 2;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.Bool("enabled", ref Enabled);
		if (version >= 2)
		{
			s.UInt32("pixelWidth", ref PixelWidth);
			s.UInt32("pixelHeight", ref PixelHeight);
			s.Float("panelWidth", ref PanelWidth);
			s.Float("panelHeight", ref PanelHeight);
			s.Bool("isInteractive", ref IsInteractive);
		}
		return .Ok;
	}

	public void Dispose() mut { }

	public static WorldUIComponentData Default => .() {
		Enabled = true,
		PixelWidth = 512,
		PixelHeight = 512,
		PanelWidth = 1.0f,
		PanelHeight = 1.0f,
		IsInteractive = true
	};
}
