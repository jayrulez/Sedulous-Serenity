using System;

namespace Sedulous.Mathematics;

/// Represents an RGBA color.
[CRepr]
struct Color : IEquatable<Color>, IHashable
{
	private uint32 mPackedValue;

	/// Initializes a new Color with the specified packed value in ABGR format.
	public this(uint32 packedValue)
	{
		mPackedValue = packedValue;
	}

	/// Initializes a new Color with the specified component values.
	public this(int32 r, int32 g, int32 b, int32 a = 255)
	{
		var r, g, b, a;
		r = Math.Clamp(r, 0, 255);
		g = Math.Clamp(g, 0, 255);
		b = Math.Clamp(b, 0, 255);
		a = Math.Clamp(a, 0, 255);

		mPackedValue = (uint32)(r | (g << 8) | (b << 16) | (a << 24));
	}

	/// Initializes a new Color with normalized float component values.
	public this(float r, float g, float b, float a = 1.0f)
	{
		var r, g, b, a;
		r = Math.Clamp(r, 0, 1);
		g = Math.Clamp(g, 0, 1);
		b = Math.Clamp(b, 0, 1);
		a = Math.Clamp(a, 0, 1);

		mPackedValue = (uint32)(
			((uint8)(r * 255)) |
			((uint32)(g * 255) << 8) |
			((uint32)(b * 255) << 16) |
			((uint32)(a * 255) << 24)
		);
	}

	/// Creates a Color from a Vector4 (RGBA normalized).
	public this(Vector4 vector)
		: this(vector.X, vector.Y, vector.Z, vector.W)
	{
	}

	// ---- Properties ----

	/// Gets the red component.
	public uint8 R => (uint8)mPackedValue;

	/// Gets the green component.
	public uint8 G => (uint8)(mPackedValue >> 8);

	/// Gets the blue component.
	public uint8 B => (uint8)(mPackedValue >> 16);

	/// Gets the alpha component.
	public uint8 A => (uint8)(mPackedValue >> 24);

	/// Gets the packed value in ABGR format.
	public uint32 PackedValue => mPackedValue;

	// ---- Static Colors ----

	public static Color Transparent => .(0, 0, 0, 0);
	public static Color Black => .(0, 0, 0, 255);
	public static Color White => .(255, 255, 255, 255);
	public static Color Red => .(255, 0, 0, 255);
	public static Color Green => .(0, 255, 0, 255);
	public static Color Blue => .(0, 0, 255, 255);
	public static Color Yellow => .(255, 255, 0, 255);
	public static Color Cyan => .(0, 255, 255, 255);
	public static Color Magenta => .(255, 0, 255, 255);
	public static Color Gray => .(128, 128, 128, 255);

	// ---- Methods ----

	/// Converts the Color to a normalized 4-vector (RGBA).
	public Vector4 ToVector4()
	{
		return Vector4(
			R / 255.0f,
			G / 255.0f,
			B / 255.0f,
			A / 255.0f
		);
	}

	/// Converts the Color to a normalized 3-vector (RGB).
	public Vector3 ToVector3()
	{
		return Vector3(
			R / 255.0f,
			G / 255.0f,
			B / 255.0f
		);
	}

	/// Creates a Color from a 32-bit integer in ARGB format.
	public static Color FromArgb(uint32 value)
	{
		let a = (uint8)(value >> 24);
		let r = (uint8)(value >> 16);
		let g = (uint8)(value >> 8);
		let b = (uint8)value;
		return Color((uint32)(r | ((uint32)g << 8) | ((uint32)b << 16) | ((uint32)a << 24)));
	}

	/// Creates a Color from a 32-bit integer in RGBA format.
	public static Color FromRgba(uint32 value)
	{
		let r = (uint8)(value >> 24);
		let g = (uint8)(value >> 16);
		let b = (uint8)(value >> 8);
		let a = (uint8)value;
		return Color((uint32)(r | ((uint32)g << 8) | ((uint32)b << 16) | ((uint32)a << 24)));
	}

	/// Converts the Color to a 32-bit integer in ARGB format.
	public uint32 ToArgb()
	{
		return ((uint32)A << 24) | ((uint32)R << 16) | ((uint32)G << 8) | B;
	}

	/// Converts the Color to a 32-bit integer in RGBA format.
	public uint32 ToRgba()
	{
		return ((uint32)R << 24) | ((uint32)G << 16) | ((uint32)B << 8) | A;
	}

	/// Linearly interpolates between two colors.
	public static Color Lerp(Color a, Color b, float t)
	{
		return Color(
			(int32)Math.Lerp((float)a.R, (float)b.R, t),
			(int32)Math.Lerp((float)a.G, (float)b.G, t),
			(int32)Math.Lerp((float)a.B, (float)b.B, t),
			(int32)Math.Lerp((float)a.A, (float)b.A, t)
		);
	}

	// ---- Operators ----

	public static Color operator *(Color color, float alpha)
	{
		let a = Math.Clamp(alpha, 0, 1);
		return Color(
			(int32)(color.R * a),
			(int32)(color.G * a),
			(int32)(color.B * a),
			(int32)(color.A * a)
		);
	}

	public static bool operator ==(Color a, Color b) => a.mPackedValue == b.mPackedValue;
	public static bool operator !=(Color a, Color b) => a.mPackedValue != b.mPackedValue;

	// ---- IEquatable / IHashable ----

	public bool Equals(Color other) => mPackedValue == other.mPackedValue;
	public int GetHashCode() => (int)mPackedValue;

	public override void ToString(String str)
	{
		str.AppendF("#{:X2}{:X2}{:X2}{:X2}", A, R, G, B);
	}
}
