"use client";

import { useEffect } from "react";

/** D-58: a page tells the Help panel which Work Order stage it shows (no data leaves the page). */
export type HelpWorkOrderContext = { id: string; reference: string; status: string; inHouse: boolean; missing?: string[] };

type Listener = (context: HelpWorkOrderContext | null) => void;
let current: HelpWorkOrderContext | null = null;
const listeners = new Set<Listener>();

export function subscribeHelpContext(listener: Listener): () => void {
  listeners.add(listener);
  listener(current);
  return () => {
    listeners.delete(listener);
  };
}

function publish(next: HelpWorkOrderContext | null) {
  current = next;
  for (const listener of listeners) listener(next);
}

export default function HelpContext({ id, reference, status, inHouse, missing = [] }: HelpWorkOrderContext) {
  const missingKey = missing.join("|");
  useEffect(() => {
    publish({ id, reference, status, inHouse, missing: missingKey ? missingKey.split("|") : [] });
    return () => publish(null);
  }, [id, reference, status, inHouse, missingKey]);
  return null;
}
