namespace Sedulous.Framework.Core.Scenes.Internal;

using Sedulous.Mathematics;

/// Internal transform data including hierarchy information and cached matrices.
/// This is stored in scene arrays and not directly exposed to users.
struct TransformData
{
	/// Local TRS values (user-facing transform).
	public Transform Local = .Identity;

	/// Cached local matrix (computed from Local TRS).
	public Matrix LocalMatrix = .Identity;

	/// Cached world matrix (LocalMatrix * parent's WorldMatrix).
	public Matrix WorldMatrix = .Identity;

	/// Parent entity ID (Invalid if this is a root entity).
	public EntityId Parent = .Invalid;

	/// Whether the local matrix needs recalculation from TRS values.
	public bool LocalDirty = true;

	/// Whether the world matrix needs recalculation.
	public bool WorldDirty = true;

	/// Creates default transform data with identity transform.
	public this()
	{
	}
}
