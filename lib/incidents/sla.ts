export function incidentSla(reportedAt: string, deadline: string, acknowledgedAt: string | null, now = new Date()) {
  const reported = new Date(reportedAt).getTime();
  const due = new Date(deadline).getTime();
  const current = now.getTime();
  const stoppedAt = acknowledgedAt ? new Date(acknowledgedAt).getTime() : current;
  const elapsedSeconds = Math.max(0, Math.floor((stoppedAt - reported) / 1000));
  const remainingSeconds = acknowledgedAt ? 0 : Math.max(0, Math.ceil((due - current) / 1000));
  const acknowledgementOverdue = !acknowledgedAt && current > due;
  return {
    acknowledged: Boolean(acknowledgedAt),
    elapsedMs: elapsedSeconds * 1000,
    elapsed_seconds: elapsedSeconds,
    elapsed_minutes: Math.floor(elapsedSeconds / 60),
    time_remaining_seconds: remainingSeconds,
    time_remaining_minutes: Math.ceil(remainingSeconds / 60),
    acknowledgement_overdue: acknowledgementOverdue,
    escalation_required: acknowledgementOverdue,
    escalationRequired: acknowledgementOverdue,
  };
}
