// © Pexilim
// Pages used to be files like privacy.html; links to them live on in sent emails and the installer, so they redirect.
const pages = ["install", "privacy", "terms", "confirm", "leave", "survey"];

export default {
  // Every response, pages and API alike: no framing (the CSP says it too, but only on pages), no type guessing, no referrer.
  async headers() {
    return [{
      source: "/:path*",
      headers: [
        { key: "X-Frame-Options", value: "DENY" },
        { key: "X-Content-Type-Options", value: "nosniff" },
        { key: "Referrer-Policy", value: "no-referrer" },
      ],
    }];
  },
  async redirects() {
    return [
      { source: "/index.html", destination: "/", permanent: true },
      ...pages.map((page) => ({ source: `/${page}.html`, destination: `/${page}`, permanent: true })),
    ];
  },
};
