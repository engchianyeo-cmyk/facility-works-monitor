import type { AssetSummary } from "@/lib/assets/types";

export const ASSET_UNAVAILABLE = "Asset unavailable";

export function assetIdentity(asset: Pick<AssetSummary, "asset_tag" | "name">) {
  return `${asset.asset_tag} · ${asset.name}`;
}

export function assetReferenceLabel(assetId: string | null | undefined, asset: Pick<AssetSummary, "asset_tag" | "name"> | null | undefined) {
  if (!assetId) return null;
  return asset ? assetIdentity(asset) : ASSET_UNAVAILABLE;
}

export function assetLocation(asset: Pick<AssetSummary, "site" | "location">) {
  return [asset.site, asset.location].filter(Boolean).join(" · ");
}

export function assetOptionLabel(asset: AssetSummary) {
  const system = asset.system?.name ? ` · ${asset.system.name}` : "";
  return `${assetIdentity(asset)}${system} · ${asset.location} · ${asset.lifecycle_status.replaceAll("_", " ")}`;
}
