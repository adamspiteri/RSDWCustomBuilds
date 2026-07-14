#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "Internationalization/Text.h"
#include "BuildPieceCatalogue.generated.h"

class UBuildingPieceData;
class UTexture2D;

/**
 * Editor-only stubs for /Script/Dominion.BuildPieceCatalogue (0.12 build menu catalogue).
 * Used to load the retoc-extracted vanilla catalogue, append mod piece entries, and save
 * to PakRaw without UAssetGUI/RSDWAssetCli.
 */
USTRUCT(BlueprintType)
struct DOMINION_API FBuildableItemCollection
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FText Label;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TArray<TSoftObjectPtr<UBuildingPieceData>> Collection;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	bool bFavouritesCategory = false;
};

USTRUCT(BlueprintType)
struct DOMINION_API FBuildPieceCataloguePage
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FText Label;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TSoftObjectPtr<UTexture2D> Icon;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TArray<FBuildableItemCollection> Collection;
};

UCLASS(BlueprintType)
class DOMINION_API UBuildPieceCatalogue : public UDataAsset
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TArray<FBuildPieceCataloguePage> Pages;

	// Game type is TSet<FString>; order in the saved asset assigns BuildingPieceDataIndex.
	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TSet<FString> AllPiecesInCatalogue;
};
