namespace Sedulous.RHI;

/// Color write mask flags.
//[Flags]
enum ColorWriteMask
{
	None = 0,
	Red = 1 << 0,
	Green = 1 << 1,
	Blue = 1 << 2,
	Alpha = 1 << 3,
	All = Red | Green | Blue | Alpha,
}

/// Describes blend state for a single color component (RGB or Alpha).
struct BlendComponent
{
	/// Blend operation.
	public BlendOperation Operation;
	/// Source blend factor.
	public BlendFactor SrcFactor;
	/// Destination blend factor.
	public BlendFactor DstFactor;

	public this()
	{
		Operation = .Add;
		SrcFactor = .One;
		DstFactor = .Zero;
	}

	public this(BlendOperation operation, BlendFactor srcFactor, BlendFactor dstFactor)
	{
		Operation = operation;
		SrcFactor = srcFactor;
		DstFactor = dstFactor;
	}

	/// Standard alpha blending for color component.
	public static Self AlphaBlendColor => .(
		.Add,
		.SrcAlpha,
		.OneMinusSrcAlpha
	);

	/// Standard alpha blending for alpha component.
	public static Self AlphaBlendAlpha => .(
		.Add,
		.One,
		.OneMinusSrcAlpha
	);
}

/// Describes blend state for a color target.
struct BlendState
{
	/// Color component blending.
	public BlendComponent Color;
	/// Alpha component blending.
	public BlendComponent Alpha;

	public this()
	{
		Color = .();
		Alpha = .();
	}

	/// Standard alpha blending (src * srcAlpha + dst * (1 - srcAlpha)).
	public static Self AlphaBlend => .() { Color = .AlphaBlendColor, Alpha = .AlphaBlendAlpha };

	/// Additive blending (src + dst).
	public static Self Additive => .()
	{
		Color = .(.Add, .One, .One),
		Alpha = .(.Add, .One, .One)
	};

	/// Multiply blending (src * dst).
	public static Self Multiply => .()
	{
		Color = .(.Add, .Dst, .Zero),
		Alpha = .(.Add, .DstAlpha, .Zero)
	};

	/// Premultiplied alpha blending (src + dst * (1 - srcAlpha)).
	public static Self PremultipliedAlpha => .()
	{
		Color = .(.Add, .One, .OneMinusSrcAlpha),
		Alpha = .(.Add, .One, .OneMinusSrcAlpha)
	};
}

/// Describes a color target in a render pipeline.
struct ColorTargetState
{
	/// Pixel format of the target.
	public TextureFormat Format;
	/// Optional blend state (null = no blending).
	public BlendState? Blend;
	/// Color write mask.
	public ColorWriteMask WriteMask;

	public this()
	{
		Format = .BGRA8Unorm;
		Blend = null;
		WriteMask = .All;
	}

	public this(TextureFormat format)
	{
		Format = format;
		Blend = null;
		WriteMask = .All;
	}

	public this(TextureFormat format, BlendState blend)
	{
		Format = format;
		Blend = blend;
		WriteMask = .All;
	}
}
