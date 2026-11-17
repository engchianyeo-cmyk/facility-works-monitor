import { getCurrentIdentity } from "@/lib/auth";
import { loadAssistantSettings } from "@/lib/assistant/settings";
import { assistantAiEnabled } from "@/lib/assistant/config";
import { createClient } from "@/lib/supabase/server";
import AssistantSettingsForm from "@/components/help/assistant-settings-form";

/** D-58: the Super-Administrator names the assistant and chooses its picture. */
export default async function AssistantAdministrationPage() {
  const identity = await getCurrentIdentity();
  if (!identity || identity.role !== "administrator") {
    return (
      <main className="mx-auto max-w-xl p-8">
        <div className="rounded-xl border border-red-200 bg-red-50 p-6">
          <h1 className="text-2xl font-bold text-red-900">Access denied</h1>
          <p className="mt-2 text-sm text-red-800">Only the Super-Administrator changes the assistant.</p>
        </div>
      </main>
    );
  }
  const settings = await loadAssistantSettings(await createClient());
  return (
    <main className="mx-auto max-w-3xl space-y-6 p-4 sm:p-8">
      <div>
        <p className="text-sm font-semibold text-blue-700">Administration</p>
        <h1 className="text-3xl font-bold tracking-tight text-slate-900">Assistant</h1>
        <p className="mt-1 text-sm text-slate-500">The helper on every page (the Help button). Change its name or picture here; everyone sees the change at once.</p>
      </div>
      <AssistantSettingsForm name={settings.name} pictureUrl={settings.pictureUrl} />
      <section className="rounded-xl border border-slate-200 bg-white p-5 text-sm text-slate-700">
        <h2 className="text-lg font-bold text-slate-900">AI answers</h2>
        <p className="mt-1">{assistantAiEnabled()
          ? "Switched on: people can ask the assistant questions in their own words."
          : "Switched off: people get the prepared answers. To switch on, the system manager adds FMW_ASSISTANT_AI=on and an ANTHROPIC_API_KEY (paid per question) to the server settings and redeploys."}</p>
        <p className="mt-2">Sounds and spoken English are chosen by each person in the Help panel on their own device.</p>
      </section>
    </main>
  );
}
