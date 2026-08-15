import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";

export default async function FirstTimePage() {
  const identity = await getCurrentIdentity();
  if (identity) redirect(identity.role === "technician" ? "/operations" : "/");

  return (
    <main className="mx-auto max-w-2xl p-6 sm:p-8">
      <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
        <p className="text-sm font-semibold text-blue-700">First-time access</p>
        <h1 className="mt-1 text-3xl font-bold tracking-tight text-slate-900">
          Accounts are invitation-only
        </h1>
        <p className="mt-3 text-sm leading-6 text-slate-600">
          Public self-registration is disabled for this customer pilot. An FMWorks
          Administrator must create or invite every account, assign its role and
          activate it before operational access is available.
        </p>
        <div className="mt-6 rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-950">
          If you received an Administrator invitation, open the link in that email.
          You will be required to set a private password before entering the app.
        </div>
        <div className="mt-6 flex flex-wrap gap-3">
          <Link href="/login" className="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-700">
            Sign in
          </Link>
          <Link href="/first-time/invitation" className="rounded-lg border border-slate-300 px-4 py-2.5 text-sm font-semibold text-slate-700 hover:bg-slate-50">
            Invitation help
          </Link>
        </div>
      </section>
    </main>
  );
}
