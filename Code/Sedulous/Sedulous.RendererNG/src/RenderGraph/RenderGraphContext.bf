namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// Context for render graph pass execution.
/// Contains all resources needed by draw systems during graph execution.
struct RenderGraphContext
{
	/// The render graph.
	public RenderGraph Graph;

	/// Scene uniform buffer (camera matrices, lighting params).
	public IBuffer SceneBuffer;

	/// Depth texture view for soft particles/depth reads.
	public ITextureView DepthTextureView;

	/// Vertex shader for the current pass.
	public IShaderModule VertexShader;

	/// Fragment shader for the current pass.
	public IShaderModule FragmentShader;

	/// Pipeline layout for the current pass.
	public IPipelineLayout PipelineLayout;

	/// Current render view.
	public RenderView View;

	/// Whether depth testing is enabled.
	public bool HasDepth;
}

/// Data for mesh rendering passes in the render graph.
struct MeshPassData
{
	/// Mesh draw system reference.
	public MeshDrawSystem DrawSystem;

	/// Mesh pool for GPU mesh lookup.
	public MeshPool MeshPool;

	/// Pipeline layout for mesh rendering.
	public IPipelineLayout PipelineLayout;

	/// Whether this is an opaque or transparent pass.
	public bool IsOpaque;
}

/// Data for particle rendering passes in the render graph.
struct ParticlePassData
{
	/// Particle draw system reference.
	public ParticleDrawSystem DrawSystem;

	/// Scene uniform buffer.
	public IBuffer SceneBuffer;

	/// Vertex shader.
	public IShaderModule VertexShader;

	/// Fragment shader.
	public IShaderModule FragmentShader;

	/// Depth texture for soft particles.
	public ITextureView DepthTexture;

	/// Whether depth testing is enabled.
	public bool HasDepth;
}

/// Data for sprite rendering passes in the render graph.
struct SpritePassData
{
	/// Sprite draw system reference.
	public SpriteDrawSystem DrawSystem;

	/// Scene uniform buffer.
	public IBuffer SceneBuffer;

	/// Vertex shader.
	public IShaderModule VertexShader;

	/// Fragment shader.
	public IShaderModule FragmentShader;

	/// Whether depth testing is enabled.
	public bool HasDepth;
}

/// Data for shadow rendering passes in the render graph.
struct ShadowPassData
{
	/// Shadow draw system reference.
	public ShadowDrawSystem DrawSystem;

	/// Mesh draw system for rendering shadow casters.
	public MeshDrawSystem MeshDrawSystem;

	/// Pipeline layout for shadow rendering.
	public IPipelineLayout PipelineLayout;

	/// Cascade index (for cascade passes).
	public uint32 CascadeIndex;

	/// Shadow region index (for local shadow passes).
	public uint32 RegionIndex;
}
