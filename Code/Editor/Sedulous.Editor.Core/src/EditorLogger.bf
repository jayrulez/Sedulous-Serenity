namespace Sedulous.Editor.Core;

using System;
using System.Collections;
using Sedulous.Logging.Abstractions;
using Sedulous.Foundation.Core;

/// A log entry stored by the editor logger.
public class LogEntry
{
	public LogLevel Level;
	public String Message ~ delete _;
	public String Category ~ delete _;
	public DateTime Timestamp;

	public this(LogLevel level, StringView message, StringView category = default)
	{
		Level = level;
		Message = new String(message);
		Category = new String(category);
		Timestamp = DateTime.Now;
	}
}

/// Logger that wraps another logger and stores messages for console display.
/// Messages are copied so they can be displayed in the editor console.
public class EditorLogger : ILogger
{
	private ILogger mInnerLogger;
	private List<LogEntry> mEntries = new .() ~ DeleteContainerAndItems!(_);
	private int mMaxEntries;
	private String mName = new .() ~ delete _;
	private LogLevel mMinimumLogLevel = .Debug;

	// Events
	private EventAccessor<delegate void(LogEntry)> mEntryAdded = new .() ~ delete _;

	/// Event fired when a new log entry is added.
	public EventAccessor<delegate void(LogEntry)> EntryAdded => mEntryAdded;

	/// All log entries.
	public List<LogEntry> Entries => mEntries;

	/// Number of entries.
	public int Count => mEntries.Count;

	/// The minimum log level to record (ILogger interface).
	public LogLevel MimimumLogLevel
	{
		get => mMinimumLogLevel;
		set => mMinimumLogLevel = value;
	}

	/// Logger name (ILogger interface).
	public String Name => mName;

	/// Creates an editor logger.
	/// @param innerLogger Optional logger to forward messages to (can be null).
	/// @param maxEntries Maximum entries to keep (oldest are removed when exceeded).
	public this(ILogger innerLogger = null, int maxEntries = 1000)
	{
		mInnerLogger = innerLogger;
		mMaxEntries = maxEntries;
		mName.Set("Editor");
	}

	/// Creates an editor logger with a name.
	public this(ILogger innerLogger, StringView name, int maxEntries = 1000)
	{
		mInnerLogger = innerLogger;
		mName.Set(name);
		mMaxEntries = maxEntries;
	}

	/// ILogger.Log implementation
	public void Log(LogLevel logLevel, StringView format, params Object[] args)
	{
		if (logLevel < mMinimumLogLevel)
			return;

		// Format the message
		let formatted = scope String();
		if (args.Count > 0)
			formatted.AppendF(format, params args);
		else
			formatted.Set(format);

		// Create entry with copied message
		let entry = new LogEntry(logLevel, formatted, mName);
		AddEntry(entry);

		// Forward to inner logger
		mInnerLogger?.Log(logLevel, format, params args);
	}

	private void AddEntry(LogEntry entry)
	{
		// Remove oldest if at capacity
		while (mEntries.Count >= mMaxEntries && mEntries.Count > 0)
		{
			let oldest = mEntries.PopFront();
			delete oldest;
		}

		mEntries.Add(entry);
		mEntryAdded.[Friend]Invoke(entry);
	}

	/// Clear all log entries.
	public void Clear()
	{
		DeleteContainerAndItems!(mEntries);
		mEntries = new .();
	}

	/// Get entries filtered by level.
	public void GetEntriesByLevel(LogLevel minLevel, List<LogEntry> outEntries)
	{
		for (let entry in mEntries)
		{
			if (entry.Level >= minLevel)
				outEntries.Add(entry);
		}
	}
}
