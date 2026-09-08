namespace MtgTtsBridge.Contracts.State;

public sealed record RuntimeCompatibilityRequestDto(string? ClientRuntimeId, string? ClientGeneratedGlobalLuaSha256);

public sealed record RuntimeCompatibilityResponseDto(
    string RuntimeCompatibilityState,
    string BridgeRevision,
    string BridgeBuildIdentity,
    string BridgeProcessInstanceId,
    DateTimeOffset BridgeProcessStartUtc,
    string? ClientRuntimeId,
    string? ClientGeneratedGlobalLuaSha256,
    string ExpectedGeneratedGlobalLuaSha256,
    string? Message = null);
