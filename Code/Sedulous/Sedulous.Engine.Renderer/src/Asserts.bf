using System;
namespace Sedulous.Engine.Renderer;

class Asserts
{
	public static void AssertStructs()
	{
		// GPULightData: 4 Vector4s = 64 bytes
		Compiler.Assert(sizeof(GPULightData) == 64);
		Compiler.Assert(alignof(GPULightData) == 4);

		// GPUClusteredLight: 4 Vector4s = 64 bytes
		Compiler.Assert(sizeof(GPUClusteredLight) == 64);
		Compiler.Assert(alignof(GPUClusteredLight) == 4);

		// ClusterAABB: 2 Vector4s = 32 bytes
		Compiler.Assert(sizeof(ClusterAABB) == 32);
		Compiler.Assert(alignof(ClusterAABB) == 4);

		// LightGridEntry: 4 uint32s = 16 bytes
		Compiler.Assert(sizeof(LightGridEntry) == 16);
		Compiler.Assert(alignof(LightGridEntry) == 4);

		// LightingUniforms: 2 Matrix (128) + 4 Vector4 (64) + 4 uint32 (16) = 208 bytes
		Compiler.Assert(sizeof(LightingUniforms) == 208);
		Compiler.Assert(alignof(LightingUniforms) == 4);

		// CascadeData: Matrix (64) + Vector4 (16) = 80 bytes
		Compiler.Assert(sizeof(CascadeData) == 80);
		Compiler.Assert(alignof(CascadeData) == 4);

		// GPUShadowTileData: Matrix (64) + Vector4 (16) + 4 int32 (16) = 96 bytes
		Compiler.Assert(sizeof(GPUShadowTileData) == 96);
		Compiler.Assert(alignof(GPUShadowTileData) == 4);

		// ShadowUniforms: CascadeData[4] (320) + GPUShadowTileData[64] (6144) + 4 fields (16) = 6480 bytes
		Compiler.Assert(sizeof(ShadowUniforms) == 6480);
		Compiler.Assert(alignof(ShadowUniforms) == 4);

		// GPUCameraData: 6 Matrix (384) + 4 Vector4 (64) = 448 bytes
		Compiler.Assert(sizeof(GPUCameraData) == 448);
		Compiler.Assert(alignof(GPUCameraData) == 4);
	}
}