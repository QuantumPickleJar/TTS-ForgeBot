namespace MtgTtsBridge.Contracts.Actions;

/// <summary>TTS library inventory used only to create Forge's local deck input.</summary>
public sealed record DeckLoadRequestDto(IReadOnlyList<DeckSeatLoadDto> Seats)
{
	public string? Format { get; init; }
	public string? FormatProvenance { get; init; }
	public bool AllowDeckMinimumOverride { get; init; }
};

public sealed record DeckSeatLoadDto(string SeatId, IReadOnlyList<DeckCardLoadDto> Cards);

public sealed record DeckCardLoadDto(string CardName, int Count);
