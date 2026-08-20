using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.Events;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Forge;

public interface IForgeAdapter
{
    string Name { get; }

    Task<AdapterStateDto> GetStateAsync(CancellationToken cancellationToken);

    Task<AdapterStateDto> StartSessionAsync(CancellationToken cancellationToken);

    Task<AdapterStateDto> ResetSessionAsync(CancellationToken cancellationToken);

    Task<ForgeChoiceResult> SubmitChoiceAsync(ChoiceRequestDto request, CancellationToken cancellationToken);

    Task<EventBatchDto> GetEventsAsync(long afterSequence, CancellationToken cancellationToken);

    Task<GameSnapshotDto?> GetSnapshotAsync(CancellationToken cancellationToken);
}
