"use client";

import { applyTerminologyOverrides } from "@/lib/product-terminology";

/** Applies the company's role and stage names before client components render labels. */
export default function TerminologyBootstrap({ labels }: { labels: Record<string, string> }) {
  applyTerminologyOverrides(labels);
  return null;
}
