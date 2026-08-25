using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Forge;

public sealed record ForgeChoiceResult(
    bool Accepted,
    AdapterStateDto State,
    string? ErrorCode,
    string? ErrorMessage,
    string? ExpectedSessionId = null,
    string? ReceivedSessionId = null);
