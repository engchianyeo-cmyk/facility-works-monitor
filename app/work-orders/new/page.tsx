import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { canCreate } from "@/lib/work-orders/permissions";
import WorkOrderForm from "@/components/work-orders/work-order-form";

export default async function NewWorkOrderPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/work-orders/new");
  if (!canCreate(identity.role)) redirect("/work-orders");
  const supabase = await createClient();
  const [{ data: categories }, { data: departments }] = await Promise.all([
    supabase.from("categories").select("id,name").order("name"),
    supabase.from("departments").select("id,code,name").eq("is_active", true).is("deleted_at", null).order("name"),
  ]);
  return <main className="mx-auto max-w-3xl space-y-6 p-6 lg:p-8"><div><h1 className="text-3xl font-bold">New Work Order</h1><p className="mt-1 text-sm text-slate-500">Save a draft or submit it directly into the authorization workflow.</p></div><WorkOrderForm categories={categories ?? []} departments={departments ?? []} /></main>;
}
