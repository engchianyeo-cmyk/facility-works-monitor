/**
 * Ollie (owner, 23 Nov 2026): "who are the users in Facility 2?" — answered from the facility's own staff list,
 * which each person may see only for their own facilities (the Super-Administrator for all).
 */
export type PeopleIntent = { roles: string[]; onCall: boolean };

const ROLE_WORDS: Array<[RegExp, string]> = [
  [/\btechnicians?\b|\btechs?\b/, "technician"],
  [/\bsupervisors?\b/, "supervisor"],
  [/\bfacility managers?\b|\bfm\b|\bmanagers?\b/, "facility_manager"],
  [/\bapprovers?\b/, "approver"],
  [/\bfinance\b|\baccounts?\b/, "finance"],
  [/\bfacility administrators?\b|\bfacility admins?\b/, "facility_administrator"],
];

/** Does the question ask about people? Returns the roles asked about (none = everyone) and whether it asks who is on call. */
export function peopleIntent(question: string): PeopleIntent | null {
  const q = ` ${question.toLowerCase()} `;
  const onCall = /\bon[- ]?call\b|\bstandby\b|\bon duty\b|\bemergency contact/.test(q);
  const roles = ROLE_WORDS.filter(([pattern]) => pattern.test(q)).map(([, role]) => role)
    // "facility manager" also matches "manager"; keep one.
    .filter((role, index, list) => list.indexOf(role) === index);
  const asksWho = /\bwho\b|\bwhom\b|\busers?\b|\bstaff\b|\bteam\b|\bpeople\b|\bpersonnel\b|\bcontacts?\b|\bphone\b|\bnumbers?\b|\blist\b|\bnames?\b/.test(q);
  if (!onCall && !(asksWho && (roles.length > 0 || /\busers?\b|\bstaff\b|\bteam\b|\bpeople\b|\bpersonnel\b|\bwho works\b/.test(q)))) return null;
  return { roles, onCall };
}

const NUMBER_WORDS: Record<string, string> = { one: "1", two: "2", three: "3", four: "4", five: "5", six: "6", seven: "7", eight: "8", nine: "9", ten: "10" };
const normalise = (text: string) => ` ${text.toLowerCase().replace(/[^a-z0-9]+/g, " ").replace(/\b(one|two|three|four|five|six|seven|eight|nine|ten)\b/g, (word) => NUMBER_WORDS[word])} `;

/** The facilities a question names ("Facility 2", "facility one", a code such as F2-PW); none named = all. */
export function facilitiesNamed<T extends { name: string; code?: string | null }>(question: string, facilities: T[]): T[] {
  const q = normalise(question);
  const named = facilities.filter((facility) => {
    const name = normalise(facility.name).trim();
    const short = name.split(" ").slice(0, 2).join(" "); // "facility 2" from "Facility 2 — Pharma Warehouse"
    const code = facility.code ? normalise(facility.code).trim() : "";
    return (name && q.includes(` ${name} `)) || (short.split(" ").length === 2 && q.includes(` ${short} `)) || (code.length >= 2 && q.includes(` ${code} `));
  });
  return named.length ? named : facilities;
}

export const ROLE_TITLES: Record<string, string> = {
  facility_administrator: "Facility Administrator", facility_manager: "Facility Manager", supervisor: "Supervisor",
  technician: "Technician", approver: "Approver", finance: "Finance",
};
export const ROLE_ORDER = ["facility_administrator", "facility_manager", "supervisor", "technician", "approver", "finance"];
