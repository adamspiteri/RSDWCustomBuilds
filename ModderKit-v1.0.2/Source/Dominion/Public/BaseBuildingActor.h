#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "BaseBuildingActor.generated.h"

/**
 * Editor-only stub of the game's /Script/Dominion.BaseBuildingActor.
 *
 * Purpose: lets the editor load an editor-only BP_T1_BasePiece stub so we can
 * author + cook a child Blueprint (BP_Stonewall). The cooked child references
 * the parent Blueprint by path, which resolves to the GAME's real classes at
 * runtime. This module is never packaged.
 *
 * IMPORTANT: this stub declares NO native subobjects. Any CreateDefaultSubobject
 * here becomes an inherited native component template baked into BP_Stonewall's
 * CDO. At runtime BP_Stonewall's parent resolves to the GAME's BaseBuildingActor,
 * which has different native components, so a phantom template (e.g. "StaticMesh")
 * fails archetype lookup -> "Could not find template object" -> fatal load crash.
 * BP_Stonewall must only carry its OWN SCS component (StonewallMesh).
 */
UCLASS()
class DOMINION_API ABaseBuildingActor : public AActor
{
	GENERATED_BODY()

public:
	ABaseBuildingActor();
};
