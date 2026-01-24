using System;
using System.Collections;

namespace Sedulous.Navigation.Detour;

/// A node in the Bounding Volume tree used for spatial acceleration of polygon queries.
[CRepr]
struct BVNode
{
	/// Minimum bounds (quantized to uint16 relative to tile bounds).
	public uint16[3] BMin;
	/// Maximum bounds (quantized to uint16 relative to tile bounds).
	public uint16[3] BMax;
	/// For leaf nodes: polygon index. For internal nodes: escape index (number of nodes to skip to reach sibling).
	public int32 Index;
}

/// Item used during BVTree construction to track polygon bounds.
struct BVItem
{
	/// Quantized minimum bounds.
	public uint16[3] BMin;
	/// Quantized maximum bounds.
	public uint16[3] BMax;
	/// Polygon index.
	public int32 PolyIndex;
}

/// Builds and queries a Bounding Volume tree for spatial acceleration of polygon queries.
/// The BVTree uses an escape-index layout: nodes are stored in depth-first order.
/// For internal nodes, Index stores the number of nodes to skip to reach the sibling subtree.
/// For leaf nodes, Index is the polygon index.
static class BVTree
{
	/// Builds a BVTree from the tile's polygons.
	/// Returns an array of BVNodes representing the tree in depth-first order.
	public static BVNode[] Build(float[] vertices, NavPoly[] polygons, int32 polyCount, float[3] tileBMin, float[3] tileBMax)
	{
		if (polyCount == 0)
			return null;

		// Create items with quantized AABB per polygon
		let items = new BVItem[polyCount];
		defer delete items;

		for (int32 i = 0; i < polyCount; i++)
		{
			ref BVItem item = ref items[i];
			item.PolyIndex = i;

			// Compute polygon AABB in world space
			ref NavPoly poly = ref polygons[i];
			float pMinX = float.MaxValue, pMinY = float.MaxValue, pMinZ = float.MaxValue;
			float pMaxX = float.MinValue, pMaxY = float.MinValue, pMaxZ = float.MinValue;

			for (int32 j = 0; j < poly.VertexCount; j++)
			{
				int32 vi = (int32)poly.VertexIndices[j] * 3;
				float vx = vertices[vi];
				float vy = vertices[vi + 1];
				float vz = vertices[vi + 2];

				if (vx < pMinX) pMinX = vx;
				if (vy < pMinY) pMinY = vy;
				if (vz < pMinZ) pMinZ = vz;
				if (vx > pMaxX) pMaxX = vx;
				if (vy > pMaxY) pMaxY = vy;
				if (vz > pMaxZ) pMaxZ = vz;
			}

			// Quantize bounds relative to tile
			item.BMin = QuantizePoint(.(pMinX, pMinY, pMinZ), tileBMin, tileBMax);
			item.BMax = QuantizePoint(.(pMaxX, pMaxY, pMaxZ), tileBMin, tileBMax);
		}

		// Allocate nodes: a complete BVTree has at most 2*n - 1 nodes
		int32 maxNodes = polyCount * 2;
		let nodes = new BVNode[maxNodes];

		int32 nodeCount = 0;
		Subdivide(items, polyCount, 0, polyCount, nodes, ref nodeCount);

		// Trim to actual count
		if (nodeCount < maxNodes)
		{
			let trimmed = new BVNode[nodeCount];
			Internal.MemCpy(trimmed.Ptr, nodes.Ptr, nodeCount * sizeof(BVNode));
			delete nodes;
			return trimmed;
		}

		return nodes;
	}

	/// Finds all leaf nodes (polygons) whose bounds overlap the query AABB.
	/// Uses non-recursive traversal via the escape index.
	public static void QueryOverlapAABB(BVNode[] nodes, int32 nodeCount, uint16[3] queryMin, uint16[3] queryMax, List<int32> results)
	{
		if (nodes == null || nodeCount == 0)
			return;

		int32 i = 0;
		while (i < nodeCount)
		{
			ref BVNode node = ref nodes[i];
			bool overlap = OverlapAABB(node.BMin, node.BMax, queryMin, queryMax);

			bool isLeaf = node.Index >= 0;

			if (isLeaf && overlap)
			{
				// Leaf node that overlaps: add the polygon index
				results.Add(node.Index);
			}

			if (overlap || isLeaf)
			{
				// Move to next node in depth-first order
				i++;
			}
			else
			{
				// Internal node that doesn't overlap: skip subtree using escape index
				i += -node.Index;
			}
		}
	}

	/// Converts a world-space point to quantized BV coordinates relative to tile bounds.
	public static uint16[3] QuantizePoint(float[3] point, float[3] tileBMin, float[3] tileBMax)
	{
		uint16[3] result = .();

		for (int32 i = 0; i < 3; i++)
		{
			float range = tileBMax[i] - tileBMin[i];
			if (range <= 0.0f)
			{
				result[i] = 0;
				continue;
			}

			float normalized = (point[i] - tileBMin[i]) / range;
			float scaled = normalized * 65535.0f;

			// Clamp to [0, 65535]
			if (scaled < 0.0f)
				result[i] = 0;
			else if (scaled > 65535.0f)
				result[i] = 65535;
			else
				result[i] = (uint16)scaled;
		}

		return result;
	}

	/// Recursively subdivides items to build the BVTree.
	private static void Subdivide(BVItem[] items, int32 itemCount, int32 start, int32 end, BVNode[] nodes, ref int32 nodeCount)
	{
		int32 thisNodeIndex = nodeCount;
		nodeCount++;

		ref BVNode node = ref nodes[thisNodeIndex];

		int32 count = end - start;

		if (count == 1)
		{
			// Leaf node
			ref BVItem item = ref items[start];
			node.BMin = item.BMin;
			node.BMax = item.BMax;
			node.Index = item.PolyIndex;
		}
		else
		{
			// Internal node: compute combined bounds
			node.BMin = items[start].BMin;
			node.BMax = items[start].BMax;

			for (int32 i = start + 1; i < end; i++)
			{
				for (int32 axis = 0; axis < 3; axis++)
				{
					if (items[i].BMin[axis] < node.BMin[axis])
						node.BMin[axis] = items[i].BMin[axis];
					if (items[i].BMax[axis] > node.BMax[axis])
						node.BMax[axis] = items[i].BMax[axis];
				}
			}

			// Find longest axis for subdivision
			int32 splitAxis = 0;
			int32 maxExtent = (int32)node.BMax[0] - (int32)node.BMin[0];

			for (int32 axis = 1; axis < 3; axis++)
			{
				int32 extent = (int32)node.BMax[axis] - (int32)node.BMin[axis];
				if (extent > maxExtent)
				{
					maxExtent = extent;
					splitAxis = axis;
				}
			}

			// Sort items along the split axis by their center
			SortItemsAlongAxis(items, start, end, splitAxis);

			// Split in half
			int32 mid = start + count / 2;

			// Recurse left subtree
			Subdivide(items, itemCount, start, mid, nodes, ref nodeCount);
			// Recurse right subtree
			Subdivide(items, itemCount, mid, end, nodes, ref nodeCount);

			// Set escape index: negative offset from this node to the node after the subtree
			node.Index = -(nodeCount - thisNodeIndex);
		}
	}

	/// Sorts items in the given range along the specified axis using insertion sort.
	private static void SortItemsAlongAxis(BVItem[] items, int32 start, int32 end, int32 axis)
	{
		for (int32 i = start + 1; i < end; i++)
		{
			BVItem key = items[i];
			int32 keyCenter = (int32)key.BMin[axis] + (int32)key.BMax[axis];

			int32 j = i - 1;
			while (j >= start)
			{
				int32 jCenter = (int32)items[j].BMin[axis] + (int32)items[j].BMax[axis];
				if (jCenter > keyCenter)
				{
					items[j + 1] = items[j];
					j--;
				}
				else
				{
					break;
				}
			}

			items[j + 1] = key;
		}
	}

	/// Tests whether two quantized AABBs overlap.
	private static bool OverlapAABB(uint16[3] aMin, uint16[3] aMax, uint16[3] bMin, uint16[3] bMax)
	{
		if (aMax[0] < bMin[0] || aMin[0] > bMax[0]) return false;
		if (aMax[1] < bMin[1] || aMin[1] > bMax[1]) return false;
		if (aMax[2] < bMin[2] || aMin[2] > bMax[2]) return false;
		return true;
	}
}
