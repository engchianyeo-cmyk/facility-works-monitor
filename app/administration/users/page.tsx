import UserManagement from "@/components/user-management";
import { getCurrentIdentity } from "@/lib/auth";

export default async function AdministrationUsersPage() {
  const identity = await getCurrentIdentity();

  if (!identity || identity.role !== "administrator") {
    return (
      <main className="mx-auto max-w-xl p-8">
        <div className="rounded-xl border border-red-200 bg-red-50 p-6">
          <h1 className="text-2xl font-bold text-red-900">Access denied</h1>
          <p className="mt-2 text-sm text-red-800">
            An active Administrator account is required to manage users.
          </p>
        </div>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-7xl space-y-6 p-6 sm:p-8">
      <div>
        <p className="text-sm font-semibold text-blue-700">Administration</p>
        <h1 className="text-3xl font-bold tracking-tight text-slate-900">
          Users
        </h1>
        <p className="mt-1 text-sm text-slate-500">
          Invite users, maintain profiles and control account access.
        </p>
      </div>
      <UserManagement currentUserId={identity.userId} />
    </main>
  );
}
