// © Pexilim
import { NextResponse } from "next/server";

// The same Content Security Policy the static pages had, plus a fresh nonce per request for Next's own inline
// scripts. No 'strict-dynamic': the site's own scripts load from 'self'. Styles keep 'unsafe-inline' for the style
// attributes in the markup (a nonce there would switch that off).
export function proxy(request) {
  const nonce = Buffer.from(crypto.randomUUID()).toString("base64");
  const dev = process.env.NODE_ENV === "development";
  const policy = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}'${dev ? " 'unsafe-eval'" : ""}`,
    "style-src 'self' 'unsafe-inline'",
    "font-src 'self'",
    "img-src 'self'",
    "media-src 'self'",
    `connect-src 'self' https://wjhvqnynjkljiqdmnyhw.supabase.co${dev ? " ws:" : ""}`,
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join("; ");
  const headers = new Headers(request.headers);
  headers.set("Content-Security-Policy", policy);
  const response = NextResponse.next({ request: { headers } });
  response.headers.set("Content-Security-Policy", policy);
  return response;
}

export const config = {
  // Pages only: not the API, Next's static files or anything with a file extension (assets, scripts, styles).
  matcher: [{ source: "/((?!api|_next/static|_next/image|_vercel|.*\\..*).*)", missing: [{ type: "header", key: "next-router-prefetch" }] }],
};
