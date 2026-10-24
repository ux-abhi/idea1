// © Pexilim
import { connection } from "next/server";
import { Analytics } from "@vercel/analytics/next";
import { SpeedInsights } from "@vercel/speed-insights/next";

export const metadata = {
  metadataBase: new URL("https://www.blinkk.app"),
  referrer: "no-referrer",
  icons: { icon: "/assets/favicon.png", apple: "/assets/apple-touch-icon.png" },
};

export const viewport = { themeColor: "#FFFFFF" };

export default async function RootLayout({ children }) {
  // Rendered per request, so each page gets the fresh CSP nonce from proxy.js.
  await connection();
  return (
    // intro-gate.js adds a class to <html> before the first paint; that's expected, not a mismatch.
    <html lang="en" suppressHydrationWarning>
      <head>
        <link rel="stylesheet" href="/css/fonts.css" />
        <link rel="stylesheet" href="/css/site.css" />
        <script src="/js/intro-gate.js" />
      </head>
      <body>
        <a className="skip" href="#main">Skip to content</a>
        {children}
        <Analytics />
        <SpeedInsights />
      </body>
    </html>
  );
}
