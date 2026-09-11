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
        // Reveal surface is a single fixed horizontal layout, not nested in main HUD.
        Assert.Equal(1, Count(xml, "id=\"BridgeHudRevealSurface\""));
        Assert.Equal(1, Count(xml, "id=\"BridgeHudRevealOverlay\""));
        Assert.Contains("Panel id=\"BridgeHudRevealOverlay\"", xml, StringComparison.Ordinal);
        Assert.Contains("rectAlignment=\"UpperLeft\"", xml, StringComparison.Ordinal);
        
        // Horizontal scrolling for multiple cards.
        Assert.Contains("HorizontalScrollView id=\"BridgeHudRevealScrollView\"", xml, StringComparison.Ordinal);
        
        // Fallback text slots for when card art cannot be resolved.
        Assert.Contains("BridgeHudRevealFallback1", xml, StringComparison.Ordinal);
        Assert.Contains("minHeight=\"170\" preferredHeight=\"170\"", xml, StringComparison.Ordinal);
        
        // Interaction buttons on each card slot.
        Assert.Contains("BridgeHudRevealCardButton1", xml, StringComparison.Ordinal);
        Assert.Contains("onClick=\"BridgeHudRevealCard\"", xml, StringComparison.Ordinal);
        
        // Close button (if lifecycle permits).
        Assert.Contains("BridgeHudRevealClose", xml, StringComparison.Ordinal);
        
        // Art source diagnostics display.
        Assert.Contains("BridgeHudRevealArtSource", xml, StringComparison.Ordinal);
        
        // Verify it's not nested under the main HUD VerticalLayout.
        var mainHudEnd = xml.IndexOf("</Panel>", xml.IndexOf("id=\"BridgeHudRoot\""));
        var revealPanel = xml.IndexOf("id=\"BridgeHudRevealOverlay\"");
        Assert.True(revealPanel > mainHudEnd, "BridgeHudRevealOverlay must be outside the main HUD Panel.");
    }

    private static int Count(string value, string needle) =>
        value.Split(needle, StringSplitOptions.None).Length - 1;

    [Fact]
    public void CardArtSlotsSizeAndPreserveAspectRatio()
    {
        var xml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.xml"));
        // Card art sizes should be substantially larger than old ~92px thumbnails.
        // New size is 170px to make actual card artwork clearly visible.
        var matches = System.Text.RegularExpressions.Regex.Matches(
            xml, @"<Image id=""BridgeHudRevealImage\d+""[^>]*minHeight=""(\d+)""");
        Assert.True(matches.Count >= 6, "Should have at least 6 image slots.");
        foreach (System.Text.RegularExpressions.Match match in matches)
        {
            var height = int.Parse(match.Groups[1].Value);
            Assert.True(height >= 170, $"Image height {height} should be >= 170px for visibility.");
        }
        Assert.Contains("preserveAspect=\"true\"", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void RevealedCardDtoIncludesImageUrlAndCardFaceIdentity()
    {
        var card = new RevealedCardDto(
            "forge:card:1", "Mountain", "mountain-face-2024", "https://example.com/art/mountain.png", "hand");
        Assert.Equal("forge:card:1", card.AuthoritativeObjectId);
        Assert.Equal("Mountain", card.CardName);
        Assert.Equal("mountain-face-2024", card.CardFaceIdentity);
        Assert.Equal("https://example.com/art/mountain.png", card.ImageUrl);
        Assert.Equal("hand", card.OriginatingZone);
    }
}
