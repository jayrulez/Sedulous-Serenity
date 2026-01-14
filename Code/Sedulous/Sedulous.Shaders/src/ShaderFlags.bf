namespace Sedulous.Shaders;

/// Shader variant flags for compile-time shader permutations.
enum ShaderFlags : uint32
{
	None = 0,

	// Geometry
	Skinned = 1 << 0,      // Vertex skinning enabled
	Instanced = 1 << 1,    // GPU instancing enabled

	// Texturing
	AlphaTest = 1 << 2,    // Alpha testing/cutout
	NormalMap = 1 << 3,    // Normal mapping enabled
	Emissive = 1 << 4,     // Emissive channel enabled

	// Depth variants (replaces pipeline duplication)
	DepthTest = 1 << 5,
	DepthWrite = 1 << 6,
	ReverseZ = 1 << 7,

	// Lighting
	ReceiveShadows = 1 << 8,
	CastShadows = 1 << 9,

	// Special modes
	Wireframe = 1 << 10,
	DoubleSided = 1 << 11,
}
