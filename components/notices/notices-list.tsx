"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export type NoticeItem = {
  id: string; ids: string[]; repeats: number; createdAt: string; read: boolean; emailStatus: string; workOrderId: string | null; workOrderLabel: string;
  text: string; href: string; waiting: boolean;
};

const sgt = (value: string) => new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Singapore" }).format(new Date(value));

async function markRead(ids: string[] | null) {
  await fetch("/api/notices/read", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ids }) }).catch(() => undefined);
}

/** D-38 (7 Nov 2026): the signed-in person's notices. Opening one marks it read and goes to the right section. */
export default function NoticesList({ items }: { items: NoticeItem[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const waiting = Array.from(new Map(items.filter((item) => item.waiting && item.workOrderId).map((item) => [item.workOrderId, item])).values());
  const unread = items.filter((item) => !item.read).length;

  async function open(item: NoticeItem) {
    if (!item.read) await markRead(item.ids);
    if (item.href) router.push(item.href); else router.refresh();
  }
  async function markAll() {
    setBusy(true);
    await markRead(null);
    setBusy(false);
    router.refresh();
  }

  if (items.length === 0) return <p className="rounded-xl border border-dashed p-6 text-slate-600">No notices yet.</p>;
  return (
    <div className="space-y-6">
      {waiting.length > 0 && (
        <section className="space-y-2">
          <h2 className="text-xl font-black">Waiting for you ({waiting.length})</h2>
          {waiting.map((item) => (
            <article key={`w-${item.id}`} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border-2 border-red-500 bg-red-50 p-4">
              <div><p className="font-black">{item.workOrderLabel}</p><p className="text-sm text-red-900">Latest: {item.text} · {sgt(item.createdAt)}</p></div>
              <button type="button" onClick={() => void open(item)} className="rounded-lg bg-red-600 px-4 py-2 text-sm font-bold text-white hover:bg-red-700">Open and act →</button>
            </article>
          ))}
        </section>
      )}
      <section className="space-y-2">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-xl font-black">All notices ({items.length}{unread ? `, ${unread} new` : ""})</h2>
          {unread > 0 && <button type="button" disabled={busy} onClick={() => void markAll()} className="rounded-lg border border-slate-300 bg-white px-4 py-2 text-sm font-bold disabled:opacity-50">Mark all as read</button>}
        </div>
        <ul className="divide-y divide-slate-100 rounded-xl border border-slate-200 bg-white">
          {items.map((item) => (
            <li key={item.id} className={`flex flex-wrap items-center justify-between gap-3 p-3 ${item.read ? "" : "bg-blue-50"}`}>
              <div className="min-w-0">
                <p className={item.read ? "text-slate-800" : "font-black text-slate-900"}>
                  {!item.read && <span className="mr-2 rounded bg-blue-700 px-2 py-0.5 text-xs font-black text-white">New</span>}
                  {item.workOrderLabel} — {item.text}{item.repeats > 1 ? ` (${item.repeats} times)` : ""}
                </p>
                <p className="text-xs text-slate-500">{sgt(item.createdAt)} · email: {item.emailStatus}</p>
              </div>
              {item.href && <button type="button" onClick={() => void open(item)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-bold text-blue-800">Open →</button>}
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
