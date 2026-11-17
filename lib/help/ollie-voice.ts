/**
 * D-58 (owner, 16 Nov 2026): the assistant's sounds and spoken English, made in the browser (Web Audio and the
 * browser's own speech voice): no sound files, no AI service, nothing sent anywhere. Preferences are kept on this
 * device. Browsers only allow sound after the person has tapped or clicked the page once.
 */
export type OlliePrefs = { sound: boolean; voice: boolean; offSince: number | null; remindedAt: number | null };
export type OllieSound = "learn" | "alert" | "test";

const KEY = "fmw.ollie.prefs";
export const REMIND_AFTER_MS = 24 * 60 * 60 * 1000;
const DEFAULTS: OlliePrefs = { sound: true, voice: false, offSince: null, remindedAt: null };

export function readPrefs(): OlliePrefs {
  try {
    const raw = window.localStorage.getItem(KEY);
    return raw ? { ...DEFAULTS, ...(JSON.parse(raw) as Partial<OlliePrefs>) } : DEFAULTS;
  } catch {
    return DEFAULTS;
  }
}

export function writePrefs(next: OlliePrefs) {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(next));
  } catch {
    /* storage blocked: preferences last for this page only */
  }
  window.dispatchEvent(new CustomEvent("fmw-ollie-prefs", { detail: next }));
}

/** Sound turned off more than a day ago, and not reminded in the last day. */
export function shouldRemind(prefs: OlliePrefs, now = Date.now()): boolean {
  if (prefs.sound || !prefs.offSince) return false;
  const since = Math.max(prefs.offSince, prefs.remindedAt ?? 0);
  return now - since >= REMIND_AFTER_MS;
}

let context: AudioContext | null = null;
function audio(): AudioContext | null {
  if (typeof window === "undefined") return null;
  const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Ctor) return null;
  context = context ?? new Ctor();
  if (context.state === "suspended") void context.resume().catch(() => undefined);
  return context;
}

/** Notes (Hz) and lengths (s): a soft rising chime to learn, a brighter three-note call for alerts. */
const TUNES: Record<OllieSound, Array<[number, number]>> = {
  learn: [[659.25, 0.16], [880, 0.28]],
  alert: [[880, 0.14], [1046.5, 0.14], [1318.5, 0.3]],
  test: [[523.25, 0.14], [659.25, 0.14], [783.99, 0.14], [1046.5, 0.3]],
};

export function playTune(kind: OllieSound, force = false) {
  if (!force && !readPrefs().sound) return;
  const ctx = audio();
  if (!ctx) return;
  let at = ctx.currentTime + 0.02;
  for (const [frequency, length] of TUNES[kind]) {
    const oscillator = ctx.createOscillator();
    const gain = ctx.createGain();
    oscillator.type = "sine";
    oscillator.frequency.value = frequency;
    gain.gain.setValueAtTime(0.0001, at);
    gain.gain.exponentialRampToValueAtTime(kind === "alert" ? 0.22 : 0.14, at + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, at + length);
    oscillator.connect(gain).connect(ctx.destination);
    oscillator.start(at);
    oscillator.stop(at + length + 0.05);
    at += length * 0.85;
  }
}

export function canSpeak(): boolean {
  return typeof window !== "undefined" && "speechSynthesis" in window;
}

/** Speaks English with the device's own voice (en-SG, en-GB or any English voice it has). */
export function speak(text: string, force = false) {
  if (!canSpeak() || (!force && !readPrefs().voice)) return;
  const synth = window.speechSynthesis;
  synth.cancel();
  const utterance = new SpeechSynthesisUtterance(text.replace(/[*_#`]/g, "").slice(0, 1200));
  const voices = synth.getVoices();
  const voice = voices.find((item) => item.lang === "en-SG") ?? voices.find((item) => item.lang === "en-GB") ?? voices.find((item) => item.lang.startsWith("en"));
  if (voice) utterance.voice = voice;
  utterance.lang = voice?.lang ?? "en-GB";
  utterance.rate = 1;
  synth.speak(utterance);
}

export function stopSpeaking() {
  if (canSpeak()) window.speechSynthesis.cancel();
}
