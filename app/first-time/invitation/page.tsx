import Link from "next/link";

export default function AdministratorInvitationPage() {
  return (
    <main className="mx-auto max-w-xl p-6 sm:p-8">
      <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
        <p className="text-sm font-semibold text-blue-700">
          Administrator invitation
        </p>
        <h1 className="mt-1 text-2xl font-bold tracking-tight text-slate-900">
          Use your secure invitation link
        </h1>
        <p className="mt-3 text-sm text-slate-600">
          Privileged accounts must use the unique first-time link issued by an
          Administrator. The invitation email and assigned role are verified
          from the secure invitation record; they cannot be selected here.
        </p>
        <p className="mt-4 rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          Invitation issuance and acceptance are not yet enabled in this
          version. Contact your Facility Works Monitor Administrator if you
          need an Initiator, Approver, Supervisor or Administrator account.
        </p>
        <div className="mt-6 flex flex-wrap gap-3">
          <Link
            href="/first-time"
            className="rounded-lg border border-slate-300 px-4 py-2.5 text-sm font-semibold text-slate-700 hover:bg-slate-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
          >
            Back to first-time access
          </Link>
          <Link
            href="/login"
            className="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
          >
            Sign in
          </Link>
        </div>
      </div>
    </main>
  );
}
