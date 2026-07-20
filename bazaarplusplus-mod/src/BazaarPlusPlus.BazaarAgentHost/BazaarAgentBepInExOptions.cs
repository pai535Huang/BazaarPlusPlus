#nullable enable
using BazaarPlusPlus.BazaarAgent;

namespace BazaarPlusPlus.BazaarAgentHost;

internal sealed class BazaarAgentBepInExOptions : IBazaarAgentOptions
{
    // Anchored on the mod data dir like Core/Paths/BepInExPathProvider. Do not derive from
    // Application.dataPath; under Proton we want writes beside the game root, not inside
    // Unity's managed asset directories.
    public string DecisionLogRoot =>
        Path.Combine(BepInEx.Paths.GameRootPath, "BazaarPlusPlusV4", "BazaarAgent");
}
