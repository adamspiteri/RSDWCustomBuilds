// Editor-only stub module so /Script/Dominion resolves during cooking.
// At runtime the real game module provides these classes; this stub is never shipped.
using UnrealBuildTool;

public class Dominion : ModuleRules
{
	public Dominion(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "GameplayTags", "AssetRegistry" });
	}
}
