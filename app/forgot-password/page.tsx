import Link from "next/link";
import PasswordRecoveryForm from "@/components/password-recovery-form";

export default function ForgotPasswordPage() {
  return (
    <main className="mx-auto max-w-md p-8">
      <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
        <h1 className="text-2xl font-bold tracking-tight">Reset your password</h1>
        <p className="mt-2 text-sm text-slate-600">Request a time-limited recovery link. The response does not reveal whether an account exists.</p>
        <PasswordRecoveryForm />
        <Link href="/login" className="mt-5 block text-center text-sm font-semibold text-blue-700 hover:underline">Back to sign in</Link>
      </section>
    </main>
  );
}
