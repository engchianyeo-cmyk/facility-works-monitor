import Link from "next/link";
import { redirect } from "next/navigation";
import AuthForm from "@/components/auth-form";
import { getCurrentIdentity } from "@/lib/auth";

export default async function RegisterPage() {
  const identity = await getCurrentIdentity();
  if (identity) redirect("/works");

  return (
    <main className="mx-auto max-w-md p-8">
      <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
        <h1 className="text-2xl font-bold tracking-tight">
          Register as a Reviewer
        </h1>
        <p className="mt-2 text-sm text-slate-500">
          Self-registration creates a Reviewer account. Higher roles must be
          assigned by an administrator.
        </p>
        <AuthForm mode="register" />
        <p className="mt-5 text-center text-sm text-slate-500">
          Already registered?{" "}
          <Link href="/login" className="font-medium text-blue-700 hover:underline">
            Sign in
          </Link>
        </p>
      </div>
    </main>
  );
}
