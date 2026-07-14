using UnrealBuildTool;
using System.Collections.Generic;

public class RSDWCustomBuildsEditorTarget : TargetRules
{
	public RSDWCustomBuildsEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.V5;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.AddRange(new string[] { "RSDWCustomBuilds", "Dominion" });
	}
}
