import { assetOptionLabel } from "@/lib/assets/presentation";
import type { AssetSummary } from "@/lib/assets/types";

export default function AssetSelector({ assets, currentAssetId, unavailable = false, name = "asset_id", label = "Asset" }: { assets: AssetSummary[]; currentAssetId?: string | null; unavailable?: boolean; name?: string; label?: string }) {
  return <label className="block text-sm font-medium">{label}<select name={name} defaultValue={currentAssetId ?? ""} className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm"><option value="">None — general facilities work</option>{unavailable && currentAssetId && <option value={currentAssetId}>Asset unavailable</option>}{assets.map((asset) => <option key={asset.id} value={asset.id}>{assetOptionLabel(asset)}</option>)}</select><span className="mt-1 block text-xs text-slate-500">Optional. Select a registered physical Asset; location remains a separate operational record.</span></label>;
}
