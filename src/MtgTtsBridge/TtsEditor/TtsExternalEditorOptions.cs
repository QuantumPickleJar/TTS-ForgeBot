namespace MtgTtsBridge.TtsEditor;

public sealed class TtsExternalEditorOptions
{
    public bool Enabled { get; set; } = true;
    public string ListenHost { get; set; } = "127.0.0.1";
    public int ListenPort { get; set; } = 39998;
    public string TtsHost { get; set; } = "127.0.0.1";
    public int TtsPort { get; set; } = 39999;
    public int OperationTimeoutSeconds { get; set; } = 120;
}
