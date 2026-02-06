namespace Sedulous.Framework.UI;

using Sedulous.Framework.Scenes;
using Sedulous.Serialization;

/// Component marking an entity as having a world-space UI panel.
/// Stores panel dimensions for serialization so panels can be recreated on load.
struct WorldUIComponent : ISerializableComponent
{
	/// Whether this UI panel is enabled.
	public bool Enabled;
	/// Render texture width in pixels.
	public uint32 PixelWidth;
	/// Render texture height in pixels.
	public uint32 PixelHeight;
	/// Panel width in world units.
	public float PanelWidth;
	/// Panel height in world units.
	public float PanelHeight;
	/// Whether this panel receives mouse input.
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

	public static WorldUIComponent Default => .() {
		Enabled = true,
		PixelWidth = 512,
		PixelHeight = 512,
		PanelWidth = 1.0f,
		PanelHeight = 1.0f,
		IsInteractive = true
	};
}
