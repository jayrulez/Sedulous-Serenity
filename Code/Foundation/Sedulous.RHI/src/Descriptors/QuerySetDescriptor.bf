namespace Sedulous.RHI;

using System;

/// Descriptor for creating a query set.
[CRepr]
struct QuerySetDescriptor
{
	/// The type of queries in this set.
	public QueryType Type;

	/// The number of queries in the set.
	public uint32 Count;

	/// Optional label for debugging.
	public char8* Label;

	public this(QueryType type, uint32 count, char8* label = null)
	{
		Type = type;
		Count = count;
		Label = label;
	}
}
