#include "BaseBuildingActor.h"

ABaseBuildingActor::ABaseBuildingActor()
{
	PrimaryActorTick.bCanEverTick = false;

	// No native subobjects on purpose. The editor gives child Blueprints a
	// DefaultSceneRoot to author against; at runtime the game's real base class
	// provides the root + components.
}
