import { redirect } from "next/navigation";
import PasswordChangeForm from "@/components/password-change-form";
import { getCurrentAccountIdentity } from "@/lib/auth";

export default async function AccountPasswordPage({
  searchParams,
}: {
  searchParams: Promise<{ setup?: string; next?: string }>;
}) {
  const identity = await getCurrentAccountIdentity();
  const parameters = await searchParams;
  if (!identity) redirect("/login?next=/account/password");
  const requestedNext = parameters.next;
  const roleDefault = identity.role === "technician" ? "/operations" : "/";
  const nextPath = requestedNext?.startsWith("/") && !requestedNext.startsWith("//")
    ? requestedNext
    : roleDefault;
  const required = identity.passwordChangeRequired || parameters.setup === "required";

  return (
    <main className="mx-auto max-w-md p-8">
      <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
        <p className="text-sm font-semibold text-blue-700">Account security</p>
        <h1 className="mt-1 text-2xl font-bold tracking-tight">
          {required ? "Set your private password" : "Change your password"}
        </h1>
        <p className="mt-2 text-sm text-slate-600">
          {required
            ? "Operational access remains locked until the temporary or invited credential is replaced."
            : "Choose a new password for your authenticated account."}
        </p>
        <PasswordChangeForm required={required} nextPath={nextPath === "/" ? roleDefault : nextPath} />
      </section>
    </main>
  );
}
