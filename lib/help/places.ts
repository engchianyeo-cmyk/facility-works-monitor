/**
 * UAT 18 Nov 2026 ("Is there a room to store morphine?"): Ollie also looks in the facility's own equipment and area
 * lists for places, using everyday words a pharma warehouse team would use. Pure helpers; the route does the lookup.
 */
const GENERIC = new Set([
  "the", "a", "an", "i", "my", "is", "are", "to", "of", "in", "on", "it", "do", "does", "how", "can", "what", "and", "for", "this",
  "be", "not", "there", "where", "which", "any", "some", "we", "our", "us", "have", "has", "room", "rooms", "store", "storing",
  "storage", "stored", "keep", "kept", "put", "place", "space", "facility", "facilities", "find", "show", "me", "please", "located",
  "location", "locate", "near", "nearest", "who", "when", "should", "could", "would", "with", "at", "or", "if", "need", "want",
]);

/** Everyday words → the words the facility lists use. */
const SYNONYMS: Array<{ words: string[]; search: string[]; note?: string }> = [
  {
    words: ["morphine", "opioid", "opioids", "narcotic", "narcotics", "fentanyl", "codeine", "oxycodone", "pethidine", "ketamine", "methadone", "cd", "cds", "controlled", "scheduled", "poison", "poisons"],
    search: ["controlled drug", "vault"],
    note: "Controlled drugs are kept only in the Controlled Drugs Vault, under the facility's licence and its controlled-drug procedures (access list, register, two-person checks). Ask the Facility Manager or the Responsible Person before storing anything there.",
  },
  { words: ["vaccine", "vaccines", "insulin", "biologic", "biologics", "fridge", "refrigerated", "chilled", "cold"], search: ["cold room", "2-8", "chill"] },
  { words: ["frozen", "freezer", "freeze"], search: ["freezer", "frozen"] },
  { words: ["flammable", "dangerous", "hazardous", "dg", "chemical", "chemicals", "solvent", "solvents", "alcohol"], search: ["dangerous goods", "flammable", "dg"] },
  { words: ["quarantine", "rejected", "recall", "recalled", "returns", "returned"], search: ["quarantine", "return", "reject"] },
  { words: ["elevator", "elevators", "lift", "lifts"], search: ["lift"] },
  { words: ["toilet", "toilets", "washroom", "restroom", "bathroom"], search: ["toilet", "wash"] },
  { words: ["aed", "defibrillator", "firstaid"], search: ["first aid", "defibrillator"] },
  { words: ["eyewash", "shower"], search: ["eyewash", "shower"] },
  { words: ["generator", "genset"], search: ["generator"] },
  { words: ["dock", "docks", "loading", "unloading", "truck"], search: ["dock", "loading"] },
];

function tokens(query: string): string[] {
  return query.toLowerCase().replace(/[^a-z0-9 ]+/g, " ").split(" ").filter(Boolean);
}

/** App words that never mean a place ("work order" must not find the "Workshop" or a "network" UPS). */
const APP_WORDS = new Set(["work", "order", "orders", "new", "need", "you", "guide", "through", "help", "step", "steps", "how", "next", "now",
  "start", "begin", "first", "time", "app", "fmworks", "ollie", "technician", "approver", "supervisor", "approve", "submit", "drawing", "photo", "quotation", "page"]);
/** Only a question about a place, or one using a place word Ollie knows (morphine, vaccine, lift…), searches the facility. */
const PLACE_INTENT = /\b(where|which room|room|rooms|store|storage|keep|kept|located|location|locate|find|is there|are there|area|vault|nearest)\b/i;

/** The words to look for in equipment names, locations and areas (at most 6, safe for a database pattern). */
export function placeTerms(query: string): string[] {
  const raw = tokens(query.replace(/first aid/gi, "firstaid"));
  const known = raw.some((word) => SYNONYMS.some((entry) => entry.words.includes(word)));
  if (!known && !PLACE_INTENT.test(query)) return [];
  const out: string[] = [];
  for (const word of raw) {
    const group = SYNONYMS.find((entry) => entry.words.includes(word));
    if (group) out.push(...group.search);
    else if (word.length > 2 && !GENERIC.has(word) && !APP_WORDS.has(word)) out.push(word);
  }
  return [...new Set(out.map((term) => term.replace(/[^a-z0-9 -]/g, "").trim()).filter((term) => term.length > 1))].slice(0, 6);
}

/** A safety note for some kinds of question (for example controlled drugs), shown with the places found. */
export function placeNote(query: string): string | null {
  const raw = tokens(query);
  return SYNONYMS.find((entry) => entry.note && entry.words.some((word) => raw.includes(word)))?.note ?? null;
}

export type FoundPlace = { facility: string; location: string; equipment: string[] };
export type FoundArea = { facility: string; code: string; name: string };
