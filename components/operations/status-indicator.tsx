import type { ReactNode } from "react";

const TONES = {
  neutral: "border-slate-300 bg-slate-100 text-slate-700",
  info: "border-blue-300 bg-blue-50 text-blue-800",
  warning: "border-amber-300 bg-amber-50 text-amber-900",
  danger: "border-red-300 bg-red-50 text-red-800",
  success: "border-emerald-300 bg-emerald-50 text-emerald-800",
} as const;

export function StatusIndicator({ children, tone = "neutral" }: { children: ReactNode; tone?: keyof typeof TONES }) {
  return <span className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-bold ${TONES[tone]}`}>{children}</span>;
}
