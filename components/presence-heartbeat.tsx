"use client";

import { usePathname } from "next/navigation";
import { useCallback, useEffect, useRef } from "react";

const HEARTBEAT_INTERVAL_MS = 2 * 60 * 1000;
const INTERACTION_THROTTLE_MS = 60 * 1000;

export default function PresenceHeartbeat() {
  const pathname = usePathname();
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
        if (response.status === 401) enabledRef.current = false;
      } catch {
        // Network loss is represented naturally as an aging presence timestamp.
      }
    },
    [pathname],
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

  return null;
}
