export type SlaClock = { startedAt: string; rectificationDeadline: string; rectifiedAt?: string | null };
export type SlaRuntime = { elapsedSeconds: number; remainingSeconds: number; consumedPercent: number; state: "on_track" | "at_risk" | "breached" | "met" };

export function evaluateSla(clock: SlaClock, asOf = new Date()): SlaRuntime {
  const start = new Date(clock.startedAt).getTime();
  const deadline = new Date(clock.rectificationDeadline).getTime();
  const stop = clock.rectifiedAt ? new Date(clock.rectifiedAt).getTime() : asOf.getTime();
  const total = Math.max(1, Math.floor((deadline-start)/1000));
  const elapsedSeconds = Math.max(0, Math.floor((stop-start)/1000));
  const remainingSeconds = Math.floor((deadline-stop)/1000);
  const consumedPercent = Math.round((elapsedSeconds/total)*10000)/100;
  const state = clock.rectifiedAt && stop<=deadline ? "met" : stop>deadline ? "breached" : consumedPercent>=75 ? "at_risk" : "on_track";
  return { elapsedSeconds, remainingSeconds, consumedPercent, state };
}

export function thresholdsReached(consumedPercent: number, criticalSafety = false) {
  const thresholds = [50,75,90,100].filter(value => consumedPercent>=value);
  return criticalSafety ? Array.from(new Set([0,...thresholds])) : thresholds;
}
