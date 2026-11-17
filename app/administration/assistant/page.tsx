import { getCurrentIdentity } from "@/lib/auth";
import { loadAssistantSettings } from "@/lib/assistant/settings";
import { assistantAiEnabled } from "@/lib/assistant/config";
import { createClient } from "@/lib/supabase/server";
import AssistantSettingsForm from "@/components/help/assistant-settings-form";
import AssistantTeaching, { type AskedQuestion, type TeamAnswerRow } from "@/components/help/assistant-teaching";

/** D-58 / M33: the assistant's name and picture (Super-Administrator) and what it learns (the facility team). */
export default async function AssistantAdministrationPage() {
  const identity = await getCurrentIdentity();
  const editor = identity && ["administrator", "facility_administrator", "facility_manager"].includes(identity.role);
  if (!identity || !editor) {
    return (
      <main className="mx-auto max-w-xl p-8">
        <div className="rounded-xl border border-red-200 bg-red-50 p-6">
          <h1 className="text-2xl font-bold text-red-900">Access denied</h1>
          <p className="mt-2 text-sm text-red-800">The Super-Administrator, Facility Administrators and Facility Managers look after the assistant.</p>
        </div>
      </main>
    );
  }
  const supabase = await createClient();
  const [settings, questions, answers] = await Promise.all([
    loadAssistantSettings(supabase),
    supabase.from("assistant_questions").select("id,asker_role,page_path,question,answered_by,matched_answer,ai_answer,helpful,created_at").order("created_at", { ascending: false }).limit(150),
    supabase.from("assistant_answers").select("id,question,answer,keywords,active,source_question_id,updated_at").order("updated_at", { ascending: false }).limit(300),
  ]);
  return (
    <main className="mx-auto max-w-4xl space-y-6 p-4 sm:p-8">
      <div>
        <p className="text-sm font-semibold text-blue-700">Administration</p>
        <h1 className="text-3xl font-bold tracking-tight text-slate-900">Assistant</h1>
        <p className="mt-1 text-sm text-slate-500">{settings.name} helps people on every page (the Help button). It learns from the questions people ask: answer the ones it could not, and it gives your answer from then on.</p>
      </div>
      <AssistantTeaching name={settings.name} questions={(questions.data ?? []) as AskedQuestion[]} answers={(answers.data ?? []) as TeamAnswerRow[]} />
      {identity.role === "administrator" && <>
        <h2 className="text-xl font-bold text-slate-900">Name and picture</h2>
        <AssistantSettingsForm name={settings.name} pictureUrl={settings.pictureUrl} />
        <section className="rounded-xl border border-slate-200 bg-white p-5 text-sm text-slate-700">
          <h2 className="text-lg font-bold text-slate-900">AI answers</h2>
          <p className="mt-1">{assistantAiEnabled()
            ? "Switched on: people can ask in their own words. Answers taught by the team are given to the AI first."
            : "Switched off: people get the prepared answers and the team's answers. To switch on, the system manager adds FMW_ASSISTANT_AI=on and an ANTHROPIC_API_KEY (paid per question) to the server settings and redeploys."}</p>
          <p className="mt-2">Sounds and spoken English are chosen by each person in the Help panel on their own device.</p>
        </section>
      </>}
    </main>
  );
}
