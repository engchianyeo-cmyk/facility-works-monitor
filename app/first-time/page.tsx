import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";

const PRIVILEGED_ROLES = [
  {
    name: "Initiator",
    description:
      "Raises formal facility work requests, maintains supporting details and responds to clarification.",
  },
  {
    name: "Approver",
    description:
      "Reviews requests, priority and evidence, then approves, rejects or returns them for clarification.",
  },
  {
    name: "Supervisor",
    description:
      "Coordinates approved work, assigns personnel, monitors progress and verifies rectification.",
  },
  {
    name: "Administrator",
    description:
      "Manages users, roles, departments, account status, configuration and authorised audit access.",
  },
] as const;

export default async function FirstTimePage() {
  const identity = await getCurrentIdentity();
  if (identity) redirect("/works");

  return (
    <main className="mx-auto max-w-5xl p-6 sm:p-8">
      <div className="max-w-2xl">
        <p className="text-sm font-semibold text-blue-700">First-time access</p>
        <h1 className="mt-1 text-3xl font-bold tracking-tight text-slate-900">
          Choose your public account type
        </h1>
        <p className="mt-2 text-sm text-slate-600">
          Public registration is available only for Reviewers and Technicians.
          A user has one primary application role in this version.
        </p>
      </div>

      <section className="mt-6 grid gap-4 sm:grid-cols-2">
        <Link
          href="/register?role=reviewer"
          className="rounded-xl border-2 border-slate-200 bg-white p-6 shadow-sm transition hover:border-blue-500 hover:shadow-md focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
        >
          <h2 className="text-xl font-bold text-slate-900">
            Register as Reviewer
          </h2>
          <p className="mt-2 text-sm text-slate-600">
            Report facility defects, provide supporting information and monitor
            rectification progress.
          </p>
          <span className="mt-5 inline-block text-sm font-semibold text-blue-700">
            Continue as Reviewer →
          </span>
        </Link>

        <Link
          href="/register?role=technician"
          className="rounded-xl border-2 border-slate-200 bg-white p-6 shadow-sm transition hover:border-blue-500 hover:shadow-md focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
        >
          <h2 className="text-xl font-bold text-slate-900">
            Register as Technician
          </h2>
          <p className="mt-2 text-sm text-slate-600">
            Attend assigned rectification work, record progress and submit
            completion evidence.
          </p>
          <span className="mt-5 inline-block text-sm font-semibold text-blue-700">
            Continue as Technician →
          </span>
        </Link>
      </section>

      <section className="mt-8 rounded-xl border border-amber-200 bg-amber-50 p-6">
        <h2 className="text-xl font-bold text-amber-950">
          Invited by Administrator?
        </h2>
        <p className="mt-2 text-sm text-amber-900">
          Initiators, Approvers, Supervisors and Administrators cannot create
          privileged accounts through public registration. They must first be
          assigned or invited by an Administrator.
        </p>
        <Link
          href="/first-time/invitation"
          className="mt-4 inline-flex rounded-lg bg-amber-900 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-amber-950 focus:outline-none focus-visible:ring-2 focus-visible:ring-amber-700 focus-visible:ring-offset-2"
        >
          I have an Administrator invitation
        </Link>

        <div className="mt-6 grid gap-3 sm:grid-cols-2">
          {PRIVILEGED_ROLES.map((role) => (
            <div
              key={role.name}
              className="rounded-lg border border-amber-200 bg-white/70 p-4"
            >
              <h3 className="font-semibold text-slate-900">{role.name}</h3>
              <p className="mt-1 text-sm text-slate-600">{role.description}</p>
            </div>
          ))}
        </div>
        <p className="mt-5 font-semibold text-amber-950">
          These roles require Administrator assignment and are not available
          for public self-registration.
        </p>
      </section>

      <p className="mt-6 rounded-lg bg-blue-50 p-4 text-sm text-blue-900">
        Each account requires a unique email address. One email address cannot
        represent multiple independent user accounts or roles.
      </p>

      <p className="mt-6 text-center text-sm text-slate-600">
        Already have an account?{" "}
        <Link href="/login" className="font-semibold text-blue-700 hover:underline">
          Sign in
        </Link>
      </p>
    </main>
  );
}
