"use client";

import { useState } from "react";

/**
 * Owner, 10 Nov 2026: a password box with an eye button on the right, so people can see what they typed
 * (useful on phones). The button's label avoids the word "password" so the box keeps a unique accessible name.
 */
export default function PasswordInput({ id, name, autoComplete, minLength, required = true, className = "" }: {
  id: string; name: string; autoComplete: string; minLength?: number; required?: boolean; className?: string;
}) {
  const [visible, setVisible] = useState(false);
  return (
    <div className="relative">
      <input id={id} name={name} type={visible ? "text" : "password"} autoComplete={autoComplete} minLength={minLength} required={required}
        autoCapitalize="none" autoCorrect="off" spellCheck={false} className={`${className} pr-12`} />
      <button type="button" onClick={() => setVisible((value) => !value)} aria-pressed={visible} aria-controls={id}
        aria-label={visible ? "Hide the characters typed" : "Show the characters typed"} title={visible ? "Hide" : "Show"}
        className="absolute inset-y-0 right-0 mt-1 flex w-11 items-center justify-center rounded-r-lg text-slate-500 hover:text-slate-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-600">
        {visible
          ? <svg aria-hidden="true" viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 3l18 18"/><path d="M10.6 10.6a2 2 0 0 0 2.8 2.8"/><path d="M9.9 5.1A10.4 10.4 0 0 1 12 5c6.5 0 10 7 10 7a17.6 17.6 0 0 1-3.2 4.2M6.6 6.6C3.9 8.4 2 12 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6"/></svg>
          : <svg aria-hidden="true" viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>}
      </button>
    </div>
  );
}
