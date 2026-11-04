"use client";

import { usePathname } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";

const HEARTBEAT_INTERVAL_MS = 2 * 60 * 1000;
const INTERACTION_THROTTLE_MS = 60 * 1000;

/**
 * UAT 5 Nov 2026: all tabs in one browser share one sign-in. If another tab signs in as someone else, this page would
 * keep showing the old person while every action is sent as the new one. The heartbeat (sent on focus, interaction
 * and every two minutes) reports who is signed in now; a mismatch shows a red banner asking to reload.
 */
export default function PresenceHeartbeat({ expectedUserId = null, expectedName = null }: { expectedUserId?: string | null; expectedName?: string | null }) {
  const pathname = usePathname();
  const [mismatch, setMismatch] = useState<{ now: string | null } | null>(null);
  const enabledRef = useRef(true);
  const lastAttemptRef = useRef(0);

  const sendHeartbeat = useCallback(
    async (force = false) => {
      if (!enabledRef.current || document.visibilityState !== "visible") return;
      const now = Date.now();
      if (!force && now - lastAttemptRef.current < INTERACTION_THROTTLE_MS) {
        return;
      }
      lastAttemptRef.current = now;

      try {
        const response = await fetch("/api/presence", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ route: pathname }),
          keepalive: true,
        });
        if (response.status === 401) {
          enabledRef.current = false;
          if (expectedUserId) setMismatch({ now: null });
          return;
        }
        const body = await response.json().catch(() => null) as { user_id?: string; display_name?: string; email?: string | null; role?: string } | null;
        if (expectedUserId && body?.user_id && body.user_id !== expectedUserId) {
          setMismatch({ now: `${body.display_name ?? "another account"}${body.email ? ` (${body.email})` : ""}${body.role ? `, ${body.role.replaceAll("_", " ")}` : ""}` });
        }
      } catch {
        // Network loss is represented naturally as an aging presence timestamp.
      }
    },
    [pathname, expectedUserId],
  );

  useEffect(() => {
    void sendHeartbeat(true);
  }, [pathname, sendHeartbeat]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      void sendHeartbeat(true);
    }, HEARTBEAT_INTERVAL_MS);
    const onVisibleOrFocus = () => {
      if (document.visibilityState === "visible") void sendHeartbeat(true);
    };
    const onInteraction = () => {
      void sendHeartbeat(false);
    };

    window.addEventListener("focus", onVisibleOrFocus);
    document.addEventListener("visibilitychange", onVisibleOrFocus);
    document.addEventListener("pointerdown", onInteraction);
    document.addEventListener("keydown", onInteraction);

    return () => {
      window.clearInterval(interval);
      window.removeEventListener("focus", onVisibleOrFocus);
      document.removeEventListener("visibilitychange", onVisibleOrFocus);
      document.removeEventListener("pointerdown", onInteraction);
      document.removeEventListener("keydown", onInteraction);
    };
  }, [sendHeartbeat]);

  if (!mismatch) return null;
  return <div role="alert" className="sticky top-0 z-50 border-b-4 border-red-800 bg-red-600 px-4 py-3 text-white">
    <div className="mx-auto flex max-w-7xl flex-wrap items-center gap-3">
      <p className="flex-1 text-sm font-bold">{mismatch.now
        ? `This page was opened as ${expectedName ?? "a different account"}, but this browser is now signed in as ${mismatch.now} (another tab changed the sign-in). Anything you do here would be sent as that account.`
        : `This page was opened as ${expectedName ?? "you"}, but this browser is now signed out (another tab signed out).`} Reload before continuing.</p>
      <button type="button" onClick={() => window.location.reload()} className="min-h-11 rounded-lg bg-white px-4 font-black text-red-700">Reload this page</button>
    </div>
  </div>;
}
