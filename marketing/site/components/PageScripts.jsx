"use client";
// © Pexilim
import { useEffect } from "react";

// The page's own scripts (eyes, demos, forms), loaded one after another once React has taken over the page, so what
// they change on it never clashes with React. "module:" marks an ES module.
export default function PageScripts({ srcs }) {
  useEffect(() => {
    let cancelled = false;
    (async () => {
      for (const entry of srcs) {
        const src = entry.replace(/^module:/, "");
        if (cancelled || document.querySelector(`script[src="${src}"]`)) continue; // once, even if React mounts twice
        await new Promise((resolve) => {
          const script = document.createElement("script");
          script.src = src;
          if (entry.startsWith("module:")) script.type = "module";
          script.onload = script.onerror = resolve;
          document.body.appendChild(script);
        });
      }
    })();
    return () => { cancelled = true; };
  }, [srcs]);
  return null;
}
