import type { MetadataRoute } from "next";

/** D-10: lets Technicians and approvers add FMWorks to their phone's home screen. */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "FMWorks",
    short_name: "FMWorks",
    description: "Facility Work Orders: raise, approve, record and close work from phone or computer.",
    start_url: "/",
    scope: "/",
    display: "standalone",
    background_color: "#f8fafc",
    theme_color: "#1d4ed8",
    icons: [
      { src: "/icons/fmworks-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icons/fmworks-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icons/fmworks-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
    shortcuts: [
      { name: "New Work Order", url: "/work-orders/new" },
      { name: "My Drafts", url: "/work-orders?view=drafts" },
    ],
  };
}
