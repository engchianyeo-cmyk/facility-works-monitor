import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";

export default async function MaintenanceLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/maintenance");
  if (identity.role === "technician") redirect("/operations");
  return children;
}
