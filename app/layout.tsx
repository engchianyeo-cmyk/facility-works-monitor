import type { Metadata, Viewport } from "next";
import "./globals.css";
import SiteHeader from "@/components/site-header";
import PresenceHeartbeat from "@/components/presence-heartbeat";
import { getBuildInfo } from "@/lib/build-info";
import TerminologyBootstrap from "@/components/terminology-bootstrap";
import { loadTerminology } from "@/lib/terminology";
import { getCurrentIdentity } from "@/lib/auth";
import HelpPanel from "@/components/help/help-panel";
import { assistantAiEnabled } from "@/lib/assistant/config";
import { DEFAULT_ASSISTANT_SETTINGS, loadAssistantSettings } from "@/lib/assistant/settings";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: {
    default: "FMWorks",
    template: "%s | FMWorks",
  },
  description:
    "FMWorks — Built with Facility Managers. Designed for Service Teams.",
  manifest: "/manifest.webmanifest",
  icons: { icon: "/icons/fmworks-192.png", apple: "/icons/apple-touch-icon.png" },
  appleWebApp: { capable: true, title: "FMWorks", statusBarStyle: "default" },
};

export const viewport: Viewport = { themeColor: "#1d4ed8", width: "device-width", initialScale: 1 };

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const build = getBuildInfo();
  const terminology = await loadTerminology();
  const identity = await getCurrentIdentity();
  const assistant = identity ? await loadAssistantSettings(await createClient()) : DEFAULT_ASSISTANT_SETTINGS;
  return (
    <html lang="en">
      <body className="min-h-screen bg-slate-50 text-slate-900 antialiased">
        <TerminologyBootstrap labels={terminology} />
        <PresenceHeartbeat expectedUserId={identity?.userId ?? null} expectedName={identity?.displayName ?? null} />
        <SiteHeader />

        <main>{children}</main>

        {/* D-58: Help guide (prepared answers) plus the AI assistant when switched on. Signed-in people only. */}
        {identity && <HelpPanel role={identity.role} aiEnabled={assistantAiEnabled()} name={assistant.name} pictureUrl={assistant.pictureUrl} />}

        <footer className="mt-16 border-t border-slate-200 bg-white">
          <div className="mx-auto max-w-7xl px-6 py-6 text-center text-xs text-slate-500">
            <span>FMWorks v{build.version}</span>
            <span className="mx-2" aria-hidden="true">·</span>
            <span>Build {build.shortCommit}</span>
            <span className="mx-2" aria-hidden="true">·</span>
            <span>{build.environmentLabel}</span>
          </div>
        </footer>
      </body>
    </html>
  );
}
