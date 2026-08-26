using Microsoft.Extensions.Logging;

namespace MtgTtsBridge.Diagnostics;

/// <summary>Captures the existing ILogger stream into the bounded diagnostic history.</summary>
public sealed class DiagnosticLoggerProvider : ILoggerProvider
{
    private readonly DiagnosticTelemetryBuffer _telemetry;

    public DiagnosticLoggerProvider(DiagnosticTelemetryBuffer telemetry) => _telemetry = telemetry;

    public ILogger CreateLogger(string categoryName) => new DiagnosticLogger(categoryName, _telemetry);
    public void Dispose() { }

    private sealed class DiagnosticLogger : ILogger
    {
        private readonly string _categoryName;
        private readonly DiagnosticTelemetryBuffer _telemetry;

        public DiagnosticLogger(string categoryName, DiagnosticTelemetryBuffer telemetry)
        {
            _categoryName = categoryName;
            _telemetry = telemetry;
        }

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => NullScope.Instance;
        public bool IsEnabled(LogLevel logLevel) => logLevel != LogLevel.None;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            if (!IsEnabled(logLevel)) return;
            var message = formatter(state, exception);
            if (string.IsNullOrWhiteSpace(message) && exception is not null) message = exception.Message;
            _telemetry.RecordBridgeLog(logLevel.ToString(), _categoryName, message, exception);
        }

        private sealed class NullScope : IDisposable
        {
            public static readonly NullScope Instance = new();
            public void Dispose() { }
        }
    }
}
