// © Pexilim
// Blink's Update Server sends each function with only its own folder and _shared (ServerInstaller.installPackage), so a
// function that imports from another function's folder deploys from the CLI but fails there ("Module not found").
Deno.test("functions import only their own files and _shared", async () => {
  const root = new URL("..", import.meta.url);
  const bad: string[] = [];
  for await (const dir of Deno.readDir(root)) {
    if (!dir.isDirectory || dir.name === "_shared") continue;
    for await (const file of Deno.readDir(new URL(`${dir.name}/`, root))) {
      if (!file.name.endsWith(".ts")) continue;
      const text = await Deno.readTextFile(new URL(`${dir.name}/${file.name}`, root));
      for (const m of text.matchAll(/from "\.\.\/([^"/]+)\//g)) if (m[1] !== "_shared") bad.push(`${dir.name}/${file.name} → ${m[1]}`);
    }
  }
  if (bad.length) throw new Error(`Cross-function imports: ${bad.join(", ")}`);
});
