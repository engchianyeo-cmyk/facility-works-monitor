"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export type NoticeItem = {
  id: string; ids: string[]; repeats: number; createdAt: string; read: boolean; emailStatus: string; workOrderId: string | null; workOrderLabel: string;
  text: string; href: string; waiting: boolean;
  /** D-43: the newest notice of a Work Order still open, or under two days old. Others go under Earlier notices. */
  current: boolean; statusLabel: string | null;
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
  const currentItems = items.filter((item) => item.current);
  const earlier = items.filter((item) => !item.current);
  const earlierUnread = earlier.filter((item) => !item.read).length;

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
          <h2 className="text-xl font-black">Current notices ({currentItems.length})</h2>
          {unread > 0 && <button type="button" disabled={busy} onClick={() => void markAll()} className="rounded-lg border border-slate-300 bg-white px-4 py-2 text-sm font-bold disabled:opacity-50">Mark all as read</button>}
        </div>
        <p className="text-sm text-slate-600">The latest notice for each Work Order that is still open, and anything from the last two days. Older notices are in Earlier notices below.</p>
        {currentItems.length === 0 ? <p className="rounded-xl border border-dashed p-4 text-slate-600">Nothing current. Older notices are below.</p> : <NoticeRows items={currentItems} onOpen={open} />}
      </section>
      {earlier.length > 0 && (
        <details className="rounded-xl border border-slate-300 bg-slate-50 p-3">
          <summary className="cursor-pointer text-lg font-black">Earlier notices ({earlier.length}{earlierUnread ? `, ${earlierUnread} not opened` : ""})</summary>
          <p className="mt-1 text-sm text-slate-600">Superseded by a later notice, or about Work Orders already closed or cancelled. Kept for reference.</p>
          <div className="mt-3"><NoticeRows items={earlier} onOpen={open} quiet /></div>
        </details>
      )}
    </div>
  );
}

function NoticeRows({ items, onOpen, quiet = false }: { items: NoticeItem[]; onOpen: (item: NoticeItem) => Promise<void>; quiet?: boolean }) {
  return (
    <ul className="divide-y divide-slate-100 rounded-xl border border-slate-200 bg-white">
      {items.map((item) => (
        <li key={item.id} className={`flex flex-wrap items-center justify-between gap-3 p-3 ${item.read || quiet ? "" : "bg-blue-50"}`}>
          <div className="min-w-0">
            <p className={item.read || quiet ? "text-slate-800" : "font-black text-slate-900"}>
              {!item.read && !quiet && <span className="mr-2 rounded bg-blue-700 px-2 py-0.5 text-xs font-black text-white">New</span>}
              {item.workOrderLabel} — {item.text}{item.repeats > 1 ? ` (${item.repeats} times)` : ""}
            </p>
            <p className="text-xs text-slate-500">{sgt(item.createdAt)}{item.statusLabel ? <> · <b>now: {item.statusLabel}</b></> : null} · email: {item.emailStatus}</p>
          </div>
          {item.href && <button type="button" onClick={() => void onOpen(item)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-bold text-blue-800">Open →</button>}
        </li>
      ))}
    </ul>
  );
}
