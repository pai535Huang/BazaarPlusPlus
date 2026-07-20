#nullable enable
namespace BazaarPlusPlus.Game.CombatReplay.Audio;

/// <summary>
/// Selects the platform-appropriate replay-audio capture backend.
///
/// Capture records the system audio OUTPUT (loopback), exactly what the player hears, because the
/// game spatialises its 3D combat/board SFX with Google Resonance Audio, whose decoded signal never
/// appears on any tappable FMOD channel group; only device-output capture records it.
///
/// <list type="bullet">
/// <item>Windows ABI / Proton: <see cref="WasapiLoopbackCaptureTap"/> (WASAPI loopback).</item>
/// <item>Other runtimes: not supported; returns a no-op so the recorder produces a silent video.</item>
/// </list>
/// </summary>
internal static class ReplayAudioCaptureFactory
{
    public static IReplayAudioCaptureTap Create(string wavFilePath)
    {
        if (
            System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(
                System.Runtime.InteropServices.OSPlatform.Windows
            )
        )
            return new WasapiLoopbackCaptureTap(wavFilePath);

        return new UnsupportedPlatformAudioCapture(wavFilePath);
    }
}

/// <summary>
/// No-op capture for platforms without a supported loopback backend. Its
/// <see cref="TryStart"/> returns false, so the recorder proceeds with a silent video and nothing is
/// captured. Replace by returning a real backend from <see cref="ReplayAudioCaptureFactory"/>.
/// </summary>
internal sealed class UnsupportedPlatformAudioCapture : IReplayAudioCaptureTap
{
    private readonly string _wavFilePath;

    public UnsupportedPlatformAudioCapture(string wavFilePath) => _wavFilePath = wavFilePath;

    public bool IsCapturing => false;
    public bool CapturedAnySamples => false;
    public long CapturedSampleFloats => 0;
    public string WavFilePath => _wavFilePath;
    public string CapturePointLabel => "unsupported-platform";
    public ReplayAudioBackend Backend => ReplayAudioBackend.Unsupported;
    public int SampleRateHz => 0;
    public int Channels => 0;
    public string SampleFormat => "none";
    public ReplayAudioFailureReasonCode FailureReason =>
        ReplayAudioFailureReasonCode.UnsupportedPlatform;
    public Exception? FailureException => null;
    public double RmsAmplitude => 0.0;
    public float PeakAmplitude => 0f;

    public ReplayAudioCaptureStartOutcome TryStart() =>
        ReplayAudioCaptureStartOutcome.Failure(ReplayAudioFailureReasonCode.UnsupportedPlatform);

    public void Stop() { }

    public void Dispose() { }
}
