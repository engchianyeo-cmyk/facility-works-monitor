import type { Metadata } from "next";
import "./globals.css";
import SiteHeader from "@/components/site-header";
import PresenceHeartbeat from "@/components/presence-heartbeat";

export const metadata: Metadata = {
  title: {
    default: "FMWorks",
    template: "%s | FMWorks",
  },
  description:
    "FMWorks — Built with Facility Managers. Designed for Service Teams.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-slate-50 text-slate-900 antialiased">
        <PresenceHeartbeat />
        <SiteHeader />

        <main>{children}</main>

        <footer className="mt-16 border-t border-slate-200 bg-white">
          <div className="mx-auto max-w-7xl px-6 py-6 text-center text-xs text-slate-500">
            FMWorks Practitioner Preview
          </div>
        </footer>
      </body>
    </html>
  );
}
