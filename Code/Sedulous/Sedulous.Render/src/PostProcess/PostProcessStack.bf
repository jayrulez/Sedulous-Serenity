namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;

/// Manages a chain of post-processing effects with ping-pong render targets.
/// Effects are executed in priority order, each reading from the previous result.
/// The stack owns registered effects and deletes them on destruction.
public class PostProcessStack
{
	private List<IPostProcessEffect> mEffects = new .() ~ DeleteContainerAndItems!(_);
	private bool mNeedsSorting = false;

	/// Registers a post-process effect.
	/// The stack takes ownership of the effect and will delete it on destruction.
	/// Effects are automatically sorted by priority when executing.
	public void RegisterEffect(IPostProcessEffect effect)
	{
		mEffects.Add(effect);
		mNeedsSorting = true;
	}

	/// Unregisters and deletes a post-process effect.
	public void UnregisterEffect(IPostProcessEffect effect)
	{
		if (mEffects.Remove(effect))
			delete effect;
	}

	/// Gets an effect by name.
	public IPostProcessEffect GetEffect(StringView name)
	{
		for (let effect in mEffects)
		{
			if (effect.Name == name)
				return effect;
		}
		return null;
	}

	/// Gets all registered effects (in priority order if sorted).
	public List<IPostProcessEffect>.Enumerator Effects => mEffects.GetEnumerator();

	/// Returns true if any effects are enabled.
	public bool HasEnabledEffects
	{
		get
		{
			for (let effect in mEffects)
			{
				if (effect.Enabled)
					return true;
			}
			return false;
		}
	}

	/// Initialize all registered effects.
	public Result<void> Initialize(IDevice device)
	{
		for (let effect in mEffects)
		{
			if (effect.Initialize(device) case .Err)
				return .Err;
		}
		return .Ok;
	}

	/// Shutdown all registered effects.
	public void Shutdown()
	{
		for (let effect in mEffects)
		{
			effect.Shutdown();
		}
	}

	/// Adds all enabled post-process passes to the render graph.
	/// Uses ping-pong targets (PostProcessA/B) for chaining effects.
	/// @param graph The render graph.
	/// @param view The current render view.
	/// @param sceneColorHandle Handle to the scene color texture (input to first effect).
	/// @param depthHandle Handle to the scene depth texture.
	/// @returns Handle to the final post-process result texture.
	public RGResourceHandle AddPasses(
		RenderGraph graph,
		RenderView view,
		RGResourceHandle sceneColorHandle,
		RGResourceHandle depthHandle)
	{
		// Sort effects by priority if needed
		if (mNeedsSorting)
		{
			mEffects.Sort(scope (a, b) => a.Priority <=> b.Priority);
			mNeedsSorting = false;
		}

		// Count enabled effects
		int enabledCount = 0;
		for (let effect in mEffects)
		{
			if (effect.Enabled)
				enabledCount++;
		}

		// If no effects enabled, return scene color directly
		if (enabledCount == 0)
			return sceneColorHandle;

		// Create ping-pong targets
		let ppDesc = TextureResourceDesc(view.Width, view.Height, .RGBA16Float, .RenderTarget | .Sampled);

		let targetA = graph.CreateTexture("PostProcessA", ppDesc);
		let targetB = graph.CreateTexture("PostProcessB", ppDesc);

		// Track current input/output
		var currentInput = sceneColorHandle;
		var currentOutput = targetA;
		bool useTargetA = true;
		int actuallyProcessed = 0;

		// Execute each enabled effect
		for (let effect in mEffects)
		{
			if (!effect.Enabled)
				continue;

			int passCountBefore = graph.PassCount;

			// Each effect may or may not add passes (e.g., based on view settings)
			effect.AddPasses(graph, view, currentInput, currentOutput, depthHandle);

			// Only swap buffers if the effect actually added passes
			if (graph.PassCount > passCountBefore)
			{
				actuallyProcessed++;
				currentInput = currentOutput;
				useTargetA = !useTargetA;
				currentOutput = useTargetA ? targetA : targetB;
			}
		}

		// If no effects actually processed, return scene color
		if (actuallyProcessed == 0)
			return sceneColorHandle;

		// Return the last written target
		return currentInput;
	}
}
