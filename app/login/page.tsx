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
        <p className="mt-5 text-center text-sm text-slate-500">
          Need an account?{" "}
          <Link href="/register" className="font-medium text-blue-700 hover:underline">
            Register as a Reviewer
          </Link>
        </p>
      </div>
    </main>
  );
}
