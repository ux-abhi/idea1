// © Pexilim
// Pages used to be files like privacy.html; links to them live on in sent emails and the installer, so they redirect.
const pages = ["install", "privacy", "terms", "confirm", "leave", "survey"];

export default {
  async redirects() {
    return [
      { source: "/index.html", destination: "/", permanent: true },
      ...pages.map((page) => ({ source: `/${page}.html`, destination: `/${page}`, permanent: true })),
    ];
  },
};
