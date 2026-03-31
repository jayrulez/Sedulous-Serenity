namespace Sedulous.RenderGraph;

using System;
using System.Collections;

/// Validation message severity.
enum ValidationSeverity
{
	Warning,
	Error,
}

/// A single validation message.
struct ValidationMessage
{
	public ValidationSeverity Severity;
	public String Message;
}

/// Validates a compiled render graph and reports potential issues.
/// Checks for uninitialized reads, redundant writes, and other problems.
static class GraphValidator
{
	/// Validates the render graph and appends any issues to the output list.
	/// Call after Compile().
	public static void Validate(RenderGraph graph, List<ValidationMessage> outMessages)
	{
		CheckUninitializedReads(graph, outMessages);
		CheckRedundantWrites(graph, outMessages);
		CheckCulledPasses(graph, outMessages);
		CheckEmptyPasses(graph, outMessages);
	}

	/// Validates and writes results as formatted text.
	public static void ValidateToString(RenderGraph graph, String outText)
	{
		let messages = scope List<ValidationMessage>();
		Validate(graph, messages);

		if (messages.Count == 0)
		{
			outText.Append("Render graph validation: OK (no issues)\n");
		}
		else
		{
			outText.AppendF(scope $"Render graph validation: {messages.Count} issue(s)\n");
			for (let msg in messages)
			{
				let severity = (msg.Severity == .Error) ? "ERROR" : "WARN";
				outText.AppendF(scope $"  [{severity}] {msg.Message}\n");
			}
		}

		// Clean up allocated message strings
		for (var msg in messages)
			delete msg.Message;
	}

	/// Detects resources that are read without a prior write.
	private static void CheckUninitializedReads(RenderGraph graph, List<ValidationMessage> outMessages)
	{
		// Track which resources have been written (by pass order in scheduled list)
		let written = scope HashSet<uint32>();

		// Imported resources are considered "written" (they come from outside)
		for (let resource in graph.Resources)
		{
			if (resource.IsImported)
				written.Add(resource.Index);
		}

		// Walk scheduled passes in order
		for (int i = 0; i < graph.ScheduledPassCount; i++)
		{
			let pass = graph.GetScheduledPass(i);

			// Check reads
			for (let access in pass.Accesses)
			{
				if (access.IsRead && !written.Contains(access.Resource.Index))
				{
					let resName = GetResourceName(graph, access.Resource.Index);
					let msg = new String();
					msg.AppendF(scope $"Pass '{pass.Name}' reads resource '{resName}' (index={access.Resource.Index}) which has no prior write");
					outMessages.Add(.() { Severity = .Error, Message = msg });
				}
			}

			// Record writes
			for (let access in pass.Accesses)
			{
				if (access.IsWrite)
					written.Add(access.Resource.Index);
			}
		}
	}

	/// Detects resources that are written multiple times without any intermediate read.
	private static void CheckRedundantWrites(RenderGraph graph, List<ValidationMessage> outMessages)
	{
		// Track last writer per resource and whether it was read since
		let lastWriter = scope Dictionary<uint32, int32>(); // resource index → scheduled pass index
		let readSinceWrite = scope HashSet<uint32>();

		for (int i = 0; i < graph.ScheduledPassCount; i++)
		{
			let pass = graph.GetScheduledPass(i);

			// Record reads
			for (let access in pass.Accesses)
			{
				if (access.IsRead)
					readSinceWrite.Add(access.Resource.Index);
			}

			// Check writes
			for (let access in pass.Accesses)
			{
				if (access.IsWrite)
				{
					int32 prevWriter;
					if (lastWriter.TryGetValue(access.Resource.Index, out prevWriter) &&
						!readSinceWrite.Contains(access.Resource.Index))
					{
						let resName = GetResourceName(graph, access.Resource.Index);
						let prevPass = graph.GetScheduledPass(prevWriter);
						let msg = new String();
						msg.AppendF(scope $"Resource '{resName}' written by pass '{pass.Name}' without any read since previous write in '{prevPass.Name}'");
						outMessages.Add(.() { Severity = .Warning, Message = msg });
					}
					lastWriter[access.Resource.Index] = (int32)i;
					readSinceWrite.Remove(access.Resource.Index);
				}
			}
		}
	}

	/// Reports culled passes as informational warnings.
	private static void CheckCulledPasses(RenderGraph graph, List<ValidationMessage> outMessages)
	{
		for (int i = 0; i < graph.PassCount; i++)
		{
			let pass = graph.GetPass(i);
			if (pass.IsCulled)
			{
				let msg = new String();
				msg.AppendF(scope $"Pass '{pass.Name}' was culled (outputs not consumed by any retained pass)");
				outMessages.Add(.() { Severity = .Warning, Message = msg });
			}
		}
	}

	/// Reports scheduled passes that have no execute callback.
	private static void CheckEmptyPasses(RenderGraph graph, List<ValidationMessage> outMessages)
	{
		for (int i = 0; i < graph.ScheduledPassCount; i++)
		{
			let pass = graph.GetScheduledPass(i);
			if (pass.ExecuteCallback == null)
			{
				let msg = new String();
				msg.AppendF(scope $"Pass '{pass.Name}' is scheduled but has no execute callback");
				outMessages.Add(.() { Severity = .Warning, Message = msg });
			}
		}
	}

	private static StringView GetResourceName(RenderGraph graph, uint32 resourceIndex)
	{
		for (let resource in graph.Resources)
		{
			if (resource.Index == resourceIndex)
				return resource.Name;
		}
		return "unknown";
	}
}
