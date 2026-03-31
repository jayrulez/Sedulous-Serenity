namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;

using internal Sedulous.Renderer;

/// Post-processing stack that chains effects between the forward pass and blit.
/// Registered as an IRenderFeature. Effects are sub-components executed in priority order.
public class PostProcessStack : IRenderFeature
{
	private IDevice mDevice;
	private RenderSystem mSystem;
	private List<IPostProcessEffect> mEffects = new .() ~ delete _;

	/// The final output texture after all effects (valid after OnAddPasses).
	public RGTexture OutputTexture;

	public StringView Name => "PostProcessStack";

	/// Registers a post-processing effect. Effects are sorted by priority.
	public void RegisterEffect(IPostProcessEffect effect)
	{
		mEffects.Add(effect);
		mEffects.Sort(scope (a, b) => a.Priority <=> b.Priority);
	}

	/// Gets a registered effect by type.
	public T GetEffect<T>() where T : class, IPostProcessEffect
	{
		for (let effect in mEffects)
		{
			if (effect.GetType() == typeof(T))
				return (T)effect;
		}
		return default;
	}

	/// Whether any effect is enabled.
	public bool HasEnabledEffects
	{
		get
		{
			for (let effect in mEffects)
				if (effect.Enabled)
					return true;
			return false;
		}
	}

	/// Called by RenderSystem before uniform upload and before features add passes.
	/// Allows effects to modify ViewContext (e.g., TAA jitter on projection matrix).
	public void ApplyPreGraph(ViewContext viewCtx, FrameContext frameCtx)
	{
		for (let effect in mEffects)
		{
			if (effect.Enabled)
				effect.OnPreGraph(viewCtx, frameCtx);
		}
	}

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;
		mSystem = initCtx.System;

		for (let effect in mEffects)
		{
			if (effect.OnInitialize(initCtx) case .Err)
				return .Err;
		}

		return .Ok;
	}

	public void OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx)
	{
		// Gather inputs from other features
		let opaqueFeature = mSystem.GetFeature<ForwardOpaqueFeature>();
		let depthFeature = mSystem.GetFeature<DepthPrepassFeature>();
		let motionFeature = mSystem.GetFeature<MotionVectorFeature>();

		if (opaqueFeature == null) return;

		var inputs = PostProcessInputs();
		inputs.SceneColor = opaqueFeature.SceneColorTexture;
		inputs.GBuffer = opaqueFeature.GBufferTexture;
		if (depthFeature != null) inputs.Depth = depthFeature.DepthTexture;
		if (motionFeature != null) inputs.MotionVectors = motionFeature.MotionVectorTexture;

		if (!inputs.SceneColor.IsValid) return;

		// Chain effects: each reads from the previous output
		var currentColor = inputs.SceneColor;

		for (let effect in mEffects)
		{
			if (!effect.Enabled) continue;

			var effectInputs = inputs;
			effectInputs.SceneColor = currentColor;

			let output = effect.OnAddPasses(graph, frameCtx, viewCtx, effectInputs);
			if (output.IsValid)
				currentColor = output;
		}

		OutputTexture = currentColor;
	}

	public void OnShutdown(IDevice device)
	{
		for (int i = mEffects.Count - 1; i >= 0; i--)
			mEffects[i].OnShutdown(device);
	}
}
