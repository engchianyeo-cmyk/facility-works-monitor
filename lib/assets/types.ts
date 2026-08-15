import type { UserRole } from "@/lib/auth";

export const ASSET_CRITICALITIES = ["critical", "high", "medium", "low"] as const;
export const ASSET_LIFECYCLE_STATUSES = ["active", "out_of_service", "decommissioned"] as const;

export type AssetCriticality = (typeof ASSET_CRITICALITIES)[number];
export type AssetLifecycleStatus = (typeof ASSET_LIFECYCLE_STATUSES)[number];

export type AssetSystemSummary = {
  id: string;
  system_code: string;
  name: string;
  site: string;
  is_active: boolean;
};

export type AssetSummary = {
  id: string;
  asset_tag: string;
  name: string;
  asset_type: string;
  criticality: AssetCriticality;
  lifecycle_status: AssetLifecycleStatus;
  site: string;
  location: string;
  system?: { name: string; system_code?: string } | null;
};

export type AssetRpcResult = {
  ok: boolean;
  code?: string;
  message?: string;
  asset?: Record<string, unknown>;
  asset_system?: Record<string, unknown>;
  work_order?: Record<string, unknown>;
  incident?: Record<string, unknown>;
};

export function canCreateAsset(role: UserRole) {
  return role === "supervisor" || role === "administrator";
}

export function canManageAsset(role: UserRole) {
  return role === "supervisor" || role === "administrator";
}

export function canCorrectAssetTag(role: UserRole) {
  return role === "administrator";
}

export function canConfigureAssetSystems(role: UserRole) {
  return role === "administrator";
}

export function canLinkWorkOrderAsset(role: UserRole) {
  return ["approver", "supervisor", "administrator"].includes(role);
}

export function canLinkIncidentAsset(role: UserRole) {
  return role === "supervisor" || role === "administrator";
}
