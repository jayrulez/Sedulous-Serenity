using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Geometry;

namespace Sedulous.Framework.Renderer;

/// Resource manager for SkeletonResource.
class SkeletonResourceManager : ResourceManager<SkeletonResource>
{
	protected override Result<SkeletonResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		// Skeleton files aren't typically loaded directly - they come from model conversion
		return .Err(.NotSupported);
	}

	protected override Result<SkeletonResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		return .Err(.NotSupported);
	}

	public override void Unload(SkeletonResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	/// Create a skeleton resource from an existing Skeleton.
	/// The resource takes ownership of the skeleton.
	public SkeletonResource CreateFromSkeleton(Skeleton skeleton, StringView name = "")
	{
		let resource = new SkeletonResource(skeleton, true);
		resource.Name.Set(name);
		return resource;
	}
}
