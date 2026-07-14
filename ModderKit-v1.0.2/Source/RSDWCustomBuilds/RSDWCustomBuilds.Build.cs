using UnrealBuildTool;

public class RSDWCustomBuilds : ModuleRules
{
	public RSDWCustomBuilds(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "Dominion" });
	}
}
