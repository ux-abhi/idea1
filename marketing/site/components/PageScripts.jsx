"use client";
// © Pexilim
import { useEffect } from "react";

// The page's own scripts (eyes, demos, forms), added once React has taken over the page, so what they change on it
// never clashes with React. async = false: they download in parallel but run in order. "module:" marks an ES module.
export default function PageScripts({ srcs }) {
  useEffect(() => {
    for (const entry of srcs) {
      const src = entry.replace(/^module:/, "");
      if (document.querySelector(`script[src="${src}"]`)) continue; // once, even if React mounts twice
      const script = document.createElement("script");
      script.src = src;
      script.async = false;
      if (entry.startsWith("module:")) script.type = "module";
      document.body.appendChild(script);
    }
  }, [srcs]);
  return null;
}
