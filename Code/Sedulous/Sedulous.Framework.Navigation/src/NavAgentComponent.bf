namespace Sedulous.Framework.Navigation;

/// Component for entities with navigation agents.
/// The AgentIndex references the agent in the CrowdManager owned by NavWorld.
struct NavAgentComponent
{
	/// Index of this agent in the CrowdManager.
	public int32 AgentIndex;
	/// Whether to sync entity transform from the agent position each frame.
	public bool SyncToTransform;

	public static NavAgentComponent Default => .() {
		AgentIndex = -1,
		SyncToTransform = true
	};
}
