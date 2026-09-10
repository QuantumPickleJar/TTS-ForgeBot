using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.TtsEditor;

namespace MtgTtsBridge.Tests;

public sealed class TtsExternalEditorServiceTests
{
    [Fact]
    public async Task SequentialOperations_CompleteWithinOneServiceLifetime()
    {
        var listenPort = GetFreeTcpPort();
        var ttsPort = GetFreeTcpPort();
        using var service = CreateService(listenPort, ttsPort, timeoutSeconds: 5);
        await service.StartAsync(CancellationToken.None);

        await using var peer = await FakeExternalEditorPeer.StartAsync(ttsPort, async command =>
        {
            if (command.MessageId == 0)
            {
                await FakeExternalEditorPeer.SendGlobalCallbackAsync(listenPort, BuildGeneratedScript('a', "seed"));
                return;
            }

            if (command.MessageId == 1)
            {
                await FakeExternalEditorPeer.SendGlobalCallbackAsync(listenPort, command.GlobalScript ?? string.Empty);
            }
        });

        var refresh = await service.RefreshAsync(CancellationToken.None);
        Assert.True(refresh.ObservedCallbackSequence > refresh.BaselineCallbackSequence);

        var firstPushScript = BuildGeneratedScript('b', "first");
        var firstPush = await service.PushGlobalAsync(
            new TtsEditorPushGlobalRequestDto(firstPushScript, new string('b', 64)),
            CancellationToken.None);
        Assert.Equal(new string('b', 64), firstPush.VerifiedGeneratedGlobalLuaSha256);

        var secondPushScript = BuildGeneratedScript('c', "second");
        var secondPush = await service.PushGlobalAsync(
            new TtsEditorPushGlobalRequestDto(secondPushScript, new string('c', 64)),
            CancellationToken.None);
        Assert.Equal(new string('c', 64), secondPush.VerifiedGeneratedGlobalLuaSha256);

        Assert.True(secondPush.ObservedCallbackSequence > firstPush.ObservedCallbackSequence);
        await service.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task ConcurrentRefreshOperations_AreSerializedByOperationGate()
    {
        var listenPort = GetFreeTcpPort();
        var ttsPort = GetFreeTcpPort();
        using var service = CreateService(listenPort, ttsPort, timeoutSeconds: 5);
        await service.StartAsync(CancellationToken.None);

        var firstCommandSeen = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseFirst = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var commandCount = 0;

        await using var peer = await FakeExternalEditorPeer.StartAsync(ttsPort, async command =>
        {
            if (command.MessageId != 0) return;

            var seen = Interlocked.Increment(ref commandCount);
            if (seen == 1)
            {
                firstCommandSeen.TrySetResult();
                await releaseFirst.Task;
                await FakeExternalEditorPeer.SendGlobalCallbackAsync(listenPort, BuildGeneratedScript('d', "first-refresh"));
                return;
            }

            await FakeExternalEditorPeer.SendGlobalCallbackAsync(listenPort, BuildGeneratedScript('e', "second-refresh"));
        });

        var firstRefreshTask = service.RefreshAsync(CancellationToken.None);
        await firstCommandSeen.Task;

        var secondRefreshTask = service.RefreshAsync(CancellationToken.None);
        await Task.Delay(150);
        Assert.Equal(1, Volatile.Read(ref commandCount));

        releaseFirst.TrySetResult();

        var first = await firstRefreshTask;
        var second = await secondRefreshTask;

        Assert.Equal(2, Volatile.Read(ref commandCount));
        Assert.True(second.BaselineCallbackSequence >= first.ObservedCallbackSequence);
        await service.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task PushGlobal_RejectsEmbeddedGeneratedShaMismatch()
    {
        var listenPort = GetFreeTcpPort();
        var ttsPort = GetFreeTcpPort();
        using var service = CreateService(listenPort, ttsPort, timeoutSeconds: 5);
        await service.StartAsync(CancellationToken.None);

        var script = BuildGeneratedScript('f', "bad-expected");
        var exception = await Assert.ThrowsAsync<TtsEditorOperationException>(() => service.PushGlobalAsync(
            new TtsEditorPushGlobalRequestDto(script, new string('0', 64)),
            CancellationToken.None));

        Assert.Equal("generated_sha_mismatch", exception.ErrorCode);
        Assert.NotNull(exception.Details);
        Assert.Equal(new string('0', 64), exception.Details!.ExpectedGeneratedGlobalLuaSha256);
        Assert.Equal(new string('f', 64), exception.Details.ActualGeneratedGlobalLuaSha256);
        await service.StopAsync(CancellationToken.None);
    }

    private static TtsExternalEditorService CreateService(int listenPort, int ttsPort, int timeoutSeconds)
    {
        var options = Options.Create(new TtsExternalEditorOptions
        {
            Enabled = true,
            ListenHost = IPAddress.Loopback.ToString(),
            ListenPort = listenPort,
            TtsHost = IPAddress.Loopback.ToString(),
            TtsPort = ttsPort,
            OperationTimeoutSeconds = timeoutSeconds
        });
        return new TtsExternalEditorService(options, NullLogger<TtsExternalEditorService>.Instance);
    }

    private static int GetFreeTcpPort()
    {
        var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        var port = ((IPEndPoint)probe.LocalEndpoint).Port;
        probe.Stop();
        return port;
    }

    private static string BuildGeneratedScript(char fill, string marker)
    {
        var hash = new string(fill, 64);
        return "-- GENERATED GLOBAL.LUA SOURCE SHA256: " + hash + "\n"
            + "BRIDGE_GENERATED_GLOBAL_LUA_SOURCE_SHA256 = \"" + hash + "\"\n"
            + "print('" + marker + "')\n";
    }

    private sealed record ExternalEditorCommand(int MessageId, string? GlobalScript);

    private sealed class FakeExternalEditorPeer : IAsyncDisposable
    {
        private readonly TcpListener _listener;
        private readonly Func<ExternalEditorCommand, Task> _onCommand;
        private readonly CancellationTokenSource _stop = new();
        private readonly Task _loop;

        private FakeExternalEditorPeer(TcpListener listener, Func<ExternalEditorCommand, Task> onCommand)
        {
            _listener = listener;
            _onCommand = onCommand;
            _loop = Task.Run(RunAsync);
        }

        public static Task<FakeExternalEditorPeer> StartAsync(int port, Func<ExternalEditorCommand, Task> onCommand)
        {
            var listener = new TcpListener(IPAddress.Loopback, port);
            listener.Start();
            return Task.FromResult(new FakeExternalEditorPeer(listener, onCommand));
        }

        public static async Task SendGlobalCallbackAsync(int callbackPort, string script)
        {
            var payload = "{" +
                "\"messageID\":1," +
                "\"scriptStates\":[{" +
                "\"name\":\"Global\"," +
                "\"guid\":\"-1\"," +
                "\"script\":" + JsonSerializer.Serialize(script) + "," +
                "\"ui\":\"\"" +
                "}]}";
            var bytes = Encoding.UTF8.GetBytes(payload);
            using var client = new TcpClient();
            await client.ConnectAsync(IPAddress.Loopback, callbackPort);
            await using var stream = client.GetStream();
            await stream.WriteAsync(bytes);
            await stream.FlushAsync();
            try { client.Client.Shutdown(SocketShutdown.Send); } catch { }
        }

        public async ValueTask DisposeAsync()
        {
            _stop.Cancel();
            try { _listener.Stop(); } catch { }
            try { await _loop; } catch { }
            _stop.Dispose();
        }

        private async Task RunAsync()
        {
            while (!_stop.Token.IsCancellationRequested)
            {
                TcpClient? client = null;
                try
                {
                    client = await _listener.AcceptTcpClientAsync(_stop.Token);
                }
                catch (OperationCanceledException) when (_stop.IsCancellationRequested)
                {
                    break;
                }
                catch (ObjectDisposedException) when (_stop.IsCancellationRequested)
                {
                    break;
                }
                catch
                {
                    continue;
                }

                _ = HandleClientAsync(client);
            }
        }

        private async Task HandleClientAsync(TcpClient client)
        {
            using (client)
            {
                await using var stream = client.GetStream();
                using var memory = new MemoryStream();
                var buffer = new byte[16 * 1024];
                while (true)
                {
                    var read = await stream.ReadAsync(buffer, _stop.Token);
                    if (read == 0) break;
                    memory.Write(buffer, 0, read);
                }

                if (memory.Length == 0) return;

                using var document = JsonDocument.Parse(memory.ToArray());
                var root = document.RootElement;
                var messageId = root.GetProperty("messageID").GetInt32();
                string? script = null;
                if (messageId == 1
                    && root.TryGetProperty("scriptStates", out var scriptStates)
                    && scriptStates.ValueKind == JsonValueKind.Array
                    && scriptStates.GetArrayLength() > 0)
                {
                    var candidate = scriptStates[0];
                    if (candidate.TryGetProperty("script", out var scriptElement) && scriptElement.ValueKind == JsonValueKind.String)
                        script = scriptElement.GetString();
                }

                await _onCommand(new ExternalEditorCommand(messageId, script));
            }
        }
    }
}
