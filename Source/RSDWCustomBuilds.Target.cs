using UnrealBuildTool;
using System.Collections.Generic;

public class RSDWCustomBuildsTarget : TargetRules
{
	public RSDWCustomBuildsTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.V5;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.AddRange(new string[] { "RSDWCustomBuilds", "Dominion" });
	}
}
