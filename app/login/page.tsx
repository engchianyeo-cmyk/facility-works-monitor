import Link from "next/link";
import { redirect } from "next/navigation";
import AuthForm from "@/components/auth-form";
import { getCurrentIdentity } from "@/lib/auth";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string }>;
}) {
  const identity = await getCurrentIdentity();
  const { next, error } = await searchParams;
  const nextPath =
    next?.startsWith("/") && !next.startsWith("//") ? next : "/works";

  if (identity) redirect(nextPath);

  return (
    <main className="mx-auto max-w-md p-8">
      <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
        <h1 className="text-2xl font-bold tracking-tight">Sign in to FMWorks</h1>
        <p className="mt-2 text-sm text-slate-500">
          Use your Supabase Authentication account.
        </p>
        {error && (
          <p role="alert" className="mt-4 text-sm text-red-700">
            {error}
          </p>
        )}
        <AuthForm mode="login" nextPath={nextPath} />
        <div className="mt-5 space-y-3 border-t border-slate-200 pt-5 text-center">
          <Link
            href="/first-time"
            className="block w-full rounded-lg border border-blue-600 px-4 py-2.5 text-sm font-semibold text-blue-700 transition hover:bg-blue-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
          >
            First-time user
          </Link>
          <p className="text-xs text-slate-500">
            New Reviewer or Technician accounts begin here.
          </p>
        </div>
      </div>
    </main>
  );
}
