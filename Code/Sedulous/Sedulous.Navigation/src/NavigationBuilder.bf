using System;
using System.Collections;
using Sedulous.Navigation.Recast;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation;

/// High-level convenience API for building navigation meshes.
static class NavigationBuilder
{
	/// Builds a navigation mesh from raw vertex and triangle data with default config.
	public static NavMesh BuildSimple(Span<float> vertices, Span<int32> triangles)
	{
		let geometry = scope InputGeometry(vertices, triangles);
		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer delete result;

		if (result.Success)
		{
			let navMesh = result.NavMesh;
			result.NavMesh = null; // Transfer ownership
			return navMesh;
		}
		return null;
	}

	/// Builds a navigation mesh from geometry with the specified config.
	public static NavMesh Build(IInputGeometryProvider geometry, in NavMeshBuildConfig config)
	{
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer delete result;

		if (result.Success)
		{
			let navMesh = result.NavMesh;
			result.NavMesh = null;
			return navMesh;
		}
		return null;
	}

	/// Creates a NavMeshBuildConfig sized for the given agent dimensions.
	public static NavMeshBuildConfig CreateConfig(float agentRadius, float agentHeight,
		float agentMaxClimb = 0.9f, float agentMaxSlope = 45.0f, float cellSize = 0.3f)
	{
		var config = NavMeshBuildConfig.Default;
		config.CellSize = cellSize;
		config.CellHeight = cellSize * 0.5f;
		config.WalkableSlopeAngle = agentMaxSlope;
		config.WalkableHeight = (int32)Math.Ceiling(agentHeight / config.CellHeight);
		config.WalkableClimb = (int32)Math.Floor(agentMaxClimb / config.CellHeight);
		config.WalkableRadius = (int32)Math.Ceiling(agentRadius / cellSize);
		return config;
	}
}
