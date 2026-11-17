/**
 * D-58 (16 Nov 2026): "Ollie", the FMWorks assistant mascot. An original drawing for FMWorks: a blue owl in a
 * yellow hard hat and an orange hi-vis vest. Pure SVG, no image file.
 */
export default function OllieMascot({ size = 40, title = "Ollie, the FMWorks assistant" }: { size?: number; title?: string }) {
  return (
    <svg viewBox="0 0 120 120" width={size} height={size} role="img" aria-label={title} focusable="false">
      <title>{title}</title>
      <ellipse cx="60" cy="74" rx="36" ry="38" fill="#1e40af" />
      <path d="M30 70 Q60 92 90 70 L92 98 Q60 118 28 98 Z" fill="#f97316" />
      <path d="M33 84 Q60 100 87 84" stroke="#e5e7eb" strokeWidth="4" fill="none" />
      <ellipse cx="60" cy="82" rx="18" ry="16" fill="#dbeafe" />
      <path d="M52 80 q4 3 8 0 M60 86 q4 3 8 0 M50 88 q4 3 8 0" stroke="#93c5fd" strokeWidth="1.6" fill="none" />
      <path d="M25 68 Q16 84 26 100 Q32 86 34 72 Z" fill="#1d4ed8" />
      <path d="M95 68 Q104 84 94 100 Q88 86 86 72 Z" fill="#1d4ed8" />
      <ellipse cx="60" cy="48" rx="34" ry="28" fill="#2563eb" />
      <circle cx="46" cy="50" r="14" fill="#fff" />
      <circle cx="74" cy="50" r="14" fill="#fff" />
      <circle cx="47" cy="51" r="6.5" fill="#0f172a" />
      <circle cx="73" cy="51" r="6.5" fill="#0f172a" />
      <circle cx="49" cy="48.5" r="2.2" fill="#fff" />
      <circle cx="75" cy="48.5" r="2.2" fill="#fff" />
      <path d="M56 60 L64 60 L60 68 Z" fill="#facc15" stroke="#ca8a04" strokeWidth="1" />
      <circle cx="36" cy="62" r="3.5" fill="#f9a8d4" opacity="0.7" />
      <circle cx="84" cy="62" r="3.5" fill="#f9a8d4" opacity="0.7" />
      <path d="M28 36 Q30 10 60 9 Q90 10 92 36 Z" fill="#facc15" />
      <rect x="22" y="33" width="76" height="7" rx="3.5" fill="#eab308" />
      <rect x="56" y="10" width="8" height="24" rx="3" fill="#fde047" />
      <path d="M40 24 l8 8 m-10 -6 a3 3 0 1 0 4 -4" stroke="#1e3a8a" strokeWidth="2.4" fill="none" strokeLinecap="round" />
      <path d="M46 110 l-4 5 M50 111 v6 M54 110 l4 5 M66 110 l-4 5 M70 111 v6 M74 110 l4 5" stroke="#f59e0b" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}

/** The Super-Administrator's picture when one is set; otherwise Ollie. */
export function AssistantAvatar({ size = 40, name = "Ollie", pictureUrl = null, decorative = false }: { size?: number; name?: string; pictureUrl?: string | null; decorative?: boolean }) {
  if (pictureUrl) {
    // eslint-disable-next-line @next/next/no-img-element -- served by the authenticated picture route
    return <img src={pictureUrl} alt={decorative ? "" : `${name}, the FMWorks assistant`} width={size} height={size} className="rounded-full object-contain" style={{ width: size, height: size }} />;
  }
  return <OllieMascot size={size} title={decorative ? "" : `${name}, the FMWorks assistant`} />;
}
