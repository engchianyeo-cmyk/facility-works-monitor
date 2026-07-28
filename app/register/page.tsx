import Link from "next/link";
import { redirect } from "next/navigation";
import AuthForm from "@/components/auth-form";
import { getCurrentIdentity } from "@/lib/auth";

export default async function RegisterPage({
  searchParams,
}: {
  searchParams: Promise<{ role?: string }>;
}) {
  const identity = await getCurrentIdentity();
  if (identity) redirect("/works");
  const { role } = await searchParams;
  if (role !== "reviewer" && role !== "technician") {
    redirect("/first-time");
  }

  const isTechnician = role === "technician";
  const responsibilities = isTechnician
    ? [
        "Attend assigned rectification work and review the defect, location, priority and drawings.",
        "Record diagnosis, action taken, progress, technical notes and support requirements accurately.",
        "Upload before-and-after photographs and completion evidence.",
        "Submit completed assigned work for verification.",
      ]
    : [
        "Report facility defects with an accurate location, description, priority and supporting photographs.",
        "Review related facility drawings and respond to clarification requests.",
        "Monitor submitted work-order progress and completion evidence.",
        "Confirm whether completed rectification appears satisfactory.",
      ];
  const privileges = isTechnician
    ? [
        "View and acknowledge assigned work.",
        "Start assigned work and update its progress.",
        "Add technical notes and completion evidence.",
        "Submit assigned rectification work for verification.",
      ]
    : [
        "Create work orders and view records permitted by policy.",
        "Edit your own work order while it remains Submitted.",
        "Add supporting information and track rectification progress.",
        "View completion evidence.",
      ];
  const restrictions = isTechnician
    ? [
        "Cannot approve requests, self-assign, edit unrelated work, verify your own completion, change roles or administer users.",
      ]
    : [
        "Cannot approve, reject, assign, perform technician actions, change roles, delete work orders or administer users.",
      ];

  return (
    <main className="mx-auto max-w-5xl p-6 sm:p-8">
      <Link
        href="/first-time"
        className="text-sm font-medium text-blue-700 hover:underline"
      >
        ← First-time access options
      </Link>
      <div className="mt-4 grid gap-6 lg:grid-cols-[1fr_420px]">
        <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
        <h1 className="text-2xl font-bold tracking-tight">
            Register as a {isTechnician ? "Technician" : "Reviewer"}
        </h1>
        <p className="mt-2 text-sm text-slate-500">
            This public registration creates one{" "}
            {isTechnician ? "Technician" : "Reviewer"} account for this email.
        </p>
          <AuthForm mode="register" registrationRole={role} />
        <p className="mt-5 text-center text-sm text-slate-500">
          Already registered?{" "}
          <Link href="/login" className="font-medium text-blue-700 hover:underline">
            Sign in
          </Link>
        </p>
        </section>

        <aside className="space-y-4">
          {[
            ["Responsibilities", responsibilities],
            ["Privileges", privileges],
            ["Restrictions", restrictions],
          ].map(([heading, items]) => (
            <section
              key={heading as string}
              className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
            >
              <h2 className="font-semibold text-slate-900">{heading}</h2>
              <ul className="mt-3 space-y-2 text-sm text-slate-600">
                {(items as string[]).map((item) => (
                  <li key={item} className="flex gap-2">
                    <span aria-hidden="true" className="text-blue-600">
                      •
                    </span>
                    <span>{item}</span>
                  </li>
                ))}
              </ul>
            </section>
          ))}
          <p className="rounded-lg bg-blue-50 p-4 text-sm text-blue-900">
            Each account requires a unique email address. One email address
            cannot represent multiple independent user accounts or roles.
          </p>
        </aside>
      </div>
    </main>
  );
}
