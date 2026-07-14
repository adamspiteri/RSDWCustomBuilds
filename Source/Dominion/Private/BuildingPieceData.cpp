#include "BuildingPieceData.h"
#include "AssetRegistry/ARFilter.h"
#include "AssetRegistry/AssetRegistryModule.h"
#include "AssetRegistry/AssetRegistryState.h"
#include "HAL/FileManager.h"
#include "Internationalization/Text.h"

bool URSDWEditorTools::RSDWSaveAssetRegistry(const TArray<FString>& PackagePaths, const FString& OutputFile)
{
	IAssetRegistry& AssetRegistry = FAssetRegistryModule::GetRegistry();

	FARFilter Filter;
	Filter.bRecursivePaths = true;
	for (const FString& Path : PackagePaths)
	{
		Filter.PackagePaths.Add(FName(*Path));
	}

	TArray<FAssetData> Assets;
	AssetRegistry.GetAssets(Filter, Assets);
	if (Assets.Num() == 0)
	{
		UE_LOG(LogTemp, Error, TEXT("RSDWSaveAssetRegistry: no assets under the given paths"));
		return false;
	}

	FAssetRegistryState State;
	for (const FAssetData& Asset : Assets)
	{
		UE_LOG(LogTemp, Display, TEXT("RSDWSaveAssetRegistry: + %s (%s)"),
			*Asset.GetObjectPathString(), *Asset.AssetClassPath.ToString());
		State.AddAssetData(new FAssetData(Asset)); // state takes ownership
	}

	FAssetRegistrySerializationOptions Options;
	AssetRegistry.InitializeSerializationOptions(Options); // ForGame target (runtime-loadable)

	TUniquePtr<FArchive> Writer(IFileManager::Get().CreateFileWriter(*OutputFile));
	if (!Writer)
	{
		UE_LOG(LogTemp, Error, TEXT("RSDWSaveAssetRegistry: cannot write %s"), *OutputFile);
		return false;
	}
	// CRITICAL: cooked/premade registries are saved through a filter-editor-only
	// archive (Header.bFilterEditorOnlyData = Ar.IsFilterEditorOnly()). Without this
	// the payload contains editor-only data and the SHIPPING game hard-crashes
	// (EXCEPTION_ACCESS_VIOLATION on the premade-registry worker) parsing it.
	Writer->SetFilterEditorOnly(true);
	const bool bSaved = State.Save(*Writer, Options);
	Writer->Close();
	return bSaved && !Writer->IsError();
}

FString URSDWEditorTools::RSDWGetTextTableKey(FText Text)
{
	if (TOptional<FString> Key = FTextInspector::GetKey(Text))
	{
		if (!Key->IsEmpty())
		{
			return *Key;
		}
	}
	return Text.ToString();
}
