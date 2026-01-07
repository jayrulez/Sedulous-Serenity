using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Unique widget identifier.
struct WidgetId : IHashable, IEquatable<WidgetId>
{
	private uint64 mValue;

	/// Creates a widget ID from a value.
	public this(uint64 value)
	{
		mValue = value;
	}

	/// Gets the invalid/null widget ID.
	public static WidgetId Invalid => WidgetId(0);

	/// Gets whether this ID is valid.
	public bool IsValid => mValue != 0;

	/// Gets the underlying value.
	public uint64 Value => mValue;

	/// Checks equality.
	public bool Equals(WidgetId other) => mValue == other.mValue;

	/// Checks equality.
	public static bool operator ==(WidgetId a, WidgetId b) => a.mValue == b.mValue;

	/// Checks inequality.
	public static bool operator !=(WidgetId a, WidgetId b) => a.mValue != b.mValue;

	/// Gets hash code.
	public int GetHashCode() => mValue.GetHashCode();

	/// Converts to string.
	public override void ToString(String str)
	{
		str.AppendF("WidgetId({0})", mValue);
	}
}

/// Font handle for font resources.
struct FontHandle : IHashable, IEquatable<FontHandle>
{
	private uint32 mValue;

	/// Creates a font handle from a value.
	public this(uint32 value)
	{
		mValue = value;
	}

	/// Gets the invalid font handle.
	public static FontHandle Invalid => FontHandle(0);

	/// Gets whether this handle is valid.
	public bool IsValid => mValue != 0;

	/// Gets the underlying value.
	public uint32 Value => mValue;

	/// Checks equality.
	public bool Equals(FontHandle other) => mValue == other.mValue;

	/// Checks equality.
	public static bool operator ==(FontHandle a, FontHandle b) => a.mValue == b.mValue;

	/// Checks inequality.
	public static bool operator !=(FontHandle a, FontHandle b) => a.mValue != b.mValue;

	/// Gets hash code.
	public int GetHashCode() => mValue.GetHashCode();
}

/// Texture handle for texture resources.
struct TextureHandle : IHashable, IEquatable<TextureHandle>
{
	private uint32 mValue;

	/// Creates a texture handle from a value.
	public this(uint32 value)
	{
		mValue = value;
	}

	/// Gets the invalid texture handle.
	public static TextureHandle Invalid => TextureHandle(0);

	/// Gets whether this handle is valid.
	public bool IsValid => mValue != 0;

	/// Gets the underlying value.
	public uint32 Value => mValue;

	/// Checks equality.
	public bool Equals(TextureHandle other) => mValue == other.mValue;

	/// Checks equality.
	public static bool operator ==(TextureHandle a, TextureHandle b) => a.mValue == b.mValue;

	/// Checks inequality.
	public static bool operator !=(TextureHandle a, TextureHandle b) => a.mValue != b.mValue;

	/// Gets hash code.
	public int GetHashCode() => mValue.GetHashCode();
}

// Type aliases for convenience - use Mathematics types directly
// Rect = RectangleF (use Sedulous.Mathematics.RectangleF)
// Color = Sedulous.Mathematics.Color
// Vector2 = Sedulous.Mathematics.Vector2
