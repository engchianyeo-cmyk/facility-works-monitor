import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";

export default async function WorksCompatibilityPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/work-orders");
  redirect("/work-orders");
}
