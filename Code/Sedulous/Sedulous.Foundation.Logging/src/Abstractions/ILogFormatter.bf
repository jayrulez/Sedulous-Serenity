using System;
namespace Sedulous.Foundation.Logging.Abstractions;

interface ILogFormatter
{
	String Format { get; }

	void Format(ILogger logger, LogLevel logLevel, StringView message, String output);
}