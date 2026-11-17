"use client";

import { useEffect } from "react";
import { playTune, speak } from "@/lib/help/ollie-voice";

const SEEN = "fmw.ollie.seenNotices";

/**
 * D-58: the assistant calls out when new notices arrive (Work Orders waiting for this person). It compares the
 * unread count with the last one heard on this device; sound and voice follow the person's settings.
 */
export default function OllieAlerts({ unread, name }: { unread: number; name: string }) {
  useEffect(() => {
    let last = 0;
    try {
      last = Number(window.sessionStorage.getItem(SEEN) ?? "0") || 0;
      window.sessionStorage.setItem(SEEN, String(unread));
    } catch {
      return;
    }
    if (unread > last) {
      const ring = () => {
        playTune("alert");
        speak(`${name} here. You have ${unread} new notice${unread === 1 ? "" : "s"} waiting. Please check My notices.`);
      };
      // Browsers allow sound only after a tap or click; wait for the first one if needed.
      const activation = (navigator as { userActivation?: { hasBeenActive: boolean } }).userActivation;
      if (activation && !activation.hasBeenActive) {
        window.addEventListener("pointerdown", ring, { once: true });
        return () => window.removeEventListener("pointerdown", ring);
      }
      ring();
    }
  }, [unread, name]);
  return null;
}
