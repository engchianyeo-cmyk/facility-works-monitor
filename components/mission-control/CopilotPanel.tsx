import SectionTitle from "@/components/ui/SectionTitle";

export type MissionRecommendation = {
  issue: string;
  impact: string;
  nextAction: string;
};

export default function CopilotPanel({
  recommendations,
}: {
  recommendations: MissionRecommendation[];
}) {
  return (
    <section className="rounded-2xl border border-blue-200 bg-blue-50/60 p-5">
      <SectionTitle eyebrow="Next decision" title="Operations Copilot" />
      <p className="mt-2 text-sm text-slate-600">
        Recommended actions based on current incidents, assignments and due dates.
      </p>
      <div className="mt-4 space-y-3">
        {recommendations.length ? (
          recommendations.map((recommendation, index) => (
            <article
              key={`${recommendation.issue}-${index}`}
              className="rounded-xl border border-blue-100 bg-white p-4"
            >
              <p className="text-xs font-black uppercase tracking-wide text-blue-700">
                {index === 0 ? "Requires attention" : "Recommended"}
              </p>
              <h3 className="mt-1 font-black text-slate-950">
                {recommendation.issue}
              </h3>
              <dl className="mt-3 space-y-2 text-sm">
                <div>
                  <dt className="font-bold text-slate-700">Operational impact</dt>
                  <dd className="text-slate-600">{recommendation.impact}</dd>
                </div>
                <div>
                  <dt className="font-bold text-slate-700">Next action</dt>
                  <dd className="text-slate-600">{recommendation.nextAction}</dd>
                </div>
              </dl>
            </article>
          ))
        ) : (
          <div className="rounded-xl border border-emerald-200 bg-white p-4 text-sm text-slate-700">
            <p className="font-bold text-emerald-800">No immediate action required</p>
            <p className="mt-1">Continue routine monitoring of operational activity.</p>
          </div>
        )}
      </div>
    </section>
  );
}
