#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "Engine/DataTable.h"
#include "GameplayTagContainer.h"
#include "BuildingPieceData.generated.h"

class UStaticMesh;
class UTexture2D;
class ABaseBuildingActor;

/**
 * Editor-only stubs of /Script/Dominion piece-data types (UE-only build backend).
 *
 * Purpose: author DA_<PieceId> assets in the editor whose class path
 * (/Script/Dominion.BuildingPieceData) resolves to the GAME's real native class at
 * runtime. Only the properties we actually SET are declared here; the pak must be
 * cooked with bUseUnversionedProperties=False (tagged, name-based property
 * serialization) so the game's full class can load our partial property set safely.
 * Property NAMES and TYPES must match the game's 0.12 serialization exactly
 * (verified against RSDWArchive DA JSON):
 *   DisplayName, Description, DisplayIcon, BuildableActor, Requirements, PieceTag,
 *   BuildingStabilityProfileRowHandle, BuildingPieceProxyData, BuildXpEvent, PersistenceID
 * This module is never shipped; assets referencing it resolve to the game module.
 */

// Editor-only placeholders for the game's item-data classes so build-cost Requirements
// can hard-reference item assets at the GAME paths (placeholder assets are never staged;
// at runtime the import paths resolve to the game's real items).
UCLASS(BlueprintType)
class DOMINION_API UItemData : public UDataAsset
{
	GENERATED_BODY()
};

UCLASS(BlueprintType)
class DOMINION_API UFuelItemData : public UItemData
{
	GENERATED_BODY()
};

USTRUCT(BlueprintType)
struct DOMINION_API FResourceRequirement
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	int32 Amount = 0;

	// Game type: item data asset (e.g. UFuelItemData). Hard reference by path.
	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TObjectPtr<UObject> ItemData = nullptr;
};

USTRUCT(BlueprintType)
struct DOMINION_API FBuildingPieceProxyData
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TSoftObjectPtr<UStaticMesh> ProxyMesh;
};

// Row-struct stub so editor-only DataTable placeholders (DT_StabilityProfile etc.)
// can be created at the game paths for hard FDataTableRowHandle references.
USTRUCT(BlueprintType)
struct DOMINION_API FStabilityProfile : public FTableRowBase
{
	GENERATED_BODY()
};

// Python-callable helpers for the UE-only build backend (UE python cannot construct
// FGameplayTag values — TagName is read-only and RequestGameplayTag is not exposed).
UCLASS()
class DOMINION_API URSDWEditorTools : public UObject
{
	GENERATED_BODY()

public:
	UFUNCTION(BlueprintCallable, Category = "RSDW")
	static FGameplayTag RSDWMakeTag(FName TagName)
	{
		return FGameplayTag::RequestGameplayTag(TagName, /*ErrorIfNotFound*/ false);
	}

	UFUNCTION(BlueprintCallable, Category = "RSDW")
	static FString RSDWGetTextTableKey(FText Text);

	// Save a FILTERED premade AssetRegistry (only assets under PackagePaths) for
	// runtime merging via LoadPremadeAssetRegistry_Plugins: the engine appends
	// <EnabledContentPlugin>/AssetRegistry.bin into the global registry at boot,
	// which makes the game's AssetManager BuildingPieceData scan (/Game/Gameplay,
	// recursive) discover our DAs NATIVELY - no Lua registration needed.
	// Filtering is mandatory: AppendState overwrites rows for duplicate object
	// paths, so shipping the full cooked registry would clobber vanilla entries
	// with our editor-only stubs (DT_StabilityProfile, BP_T1_BasePiece, ...).
	UFUNCTION(BlueprintCallable, Category = "RSDW")
	static bool RSDWSaveAssetRegistry(const TArray<FString>& PackagePaths, const FString& OutputFile);
};

// UPrimaryDataAsset (not UDataAsset): the game's AssetManager scan requires the
// registry row to carry PrimaryAssetType/PrimaryAssetName tags, which UObject bakes
// at save time only when GetPrimaryAssetId() is valid. UPrimaryDataAsset yields
// (BuildingPieceData, <AssetName>) - exactly what the scan expects; plain UDataAsset
// rows get "Ignoring primary asset ... invalid primary asset ID" and are skipped.
// No UPROPERTYs are added, so tagged serialization of the DA is unchanged.
UCLASS(BlueprintType)
class DOMINION_API UBuildingPieceData : public UPrimaryDataAsset
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FText DisplayName;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FText Description;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TSoftObjectPtr<UTexture2D> DisplayIcon;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TSoftClassPtr<ABaseBuildingActor> BuildableActor;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	TArray<FResourceRequirement> Requirements;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FGameplayTag PieceTag;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FDataTableRowHandle BuildingStabilityProfileRowHandle;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FBuildingPieceProxyData BuildingPieceProxyData;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FDataTableRowHandle BuildXpEvent;

	UPROPERTY(EditAnywhere, BlueprintReadWrite)
	FString PersistenceID;
};
