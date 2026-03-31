namespace Sedulous.RenderGraph;

using System;
using System.Collections;

/// Handles topological sort, culling, multi-queue assignment,
/// and transient resource lifetime computation.
///
/// Note: The core scheduling and culling logic for Phase 1-2 is
/// implemented directly in RenderGraph.ScheduleAndCull().
/// This class will be expanded in Phase 6 for multi-queue scheduling.
static class PassScheduler
{
	/// Detects dependency cycles in the pass graph.
	/// Returns true if a cycle is detected.
	public static bool HasCycle(List<RenderGraphPass> passes, List<List<int32>> dependencies)
	{
		let passCount = passes.Count;
		let visited = scope bool[passCount];
		let inStack = scope bool[passCount];

		for (int i = 0; i < passCount; i++)
		{
			if (!visited[i] && HasCycleDFS(i, dependencies, visited, inStack))
				return true;
		}

		return false;
	}

	private static bool HasCycleDFS(int node, List<List<int32>> dependencies,
		bool[] visited, bool[] inStack)
	{
		visited[node] = true;
		inStack[node] = true;

		for (let dep in dependencies[node])
		{
			if (!visited[dep])
			{
				if (HasCycleDFS(dep, dependencies, visited, inStack))
					return true;
			}
			else if (inStack[dep])
			{
				return true;
			}
		}

		inStack[node] = false;
		return false;
	}
}
