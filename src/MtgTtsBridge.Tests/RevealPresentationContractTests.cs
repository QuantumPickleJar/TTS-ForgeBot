using System.Text.Json;
using MtgTtsBridge.Contracts.Events;

namespace MtgTtsBridge.Tests;

public sealed class RevealPresentationContractTests
{
    [Fact]
    public void RevealPayloadSerializesStructuredIdentityAndVisibility()
    {
        var reveal = new RevealPresentationDto(
            "reveal-1", 42, "forge:source:7", "Impulse", "forge-player-1",
            ["forge-player-1"], "private",
            [new RevealedCardDto("forge:card:8", "Island", "island-face", "https://art/island", "library")],
            "Look at the top card", true, "decision-2");

        var json = JsonSerializer.Serialize(new AuthoritativeEventDto(
            42, "event-42", "reveal", "forge-player-1", null, null, null, null, null,
            "A card was revealed.", DateTimeOffset.UnixEpoch, RevealPresentation: reveal),
            new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });

        Assert.Contains("\"revealPresentation\"", json, StringComparison.Ordinal);
        Assert.Contains("\"presentationId\":\"reveal-1\"", json, StringComparison.Ordinal);
        Assert.Contains("\"entitledViewerSeatIds\":[\"forge-player-1\"]", json, StringComparison.Ordinal);
        Assert.Contains("\"authoritativeObjectId\":\"forge:card:8\"", json, StringComparison.Ordinal);
    }

    [Fact]
    public void XmlDefinesOneFixedHorizontalRevealSurfaceWithFallbackSlots()
    {
        var xml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.xml"));
        Assert.Equal(1, Count(xml, "id=\"BridgeHudRevealSurface\""));
        Assert.Contains("HorizontalScrollView id=\"BridgeHudRevealScrollView\"", xml, StringComparison.Ordinal);
        Assert.Contains("BridgeHudRevealFallback1", xml, StringComparison.Ordinal);
        Assert.Contains("BridgeHudRevealClose", xml, StringComparison.Ordinal);
    }

    private static int Count(string value, string needle) =>
        value.Split(needle, StringSplitOptions.None).Length - 1;
}
