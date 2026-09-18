import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createMarkdownRenderer, defineLoader } from "vitepress";
import { syntaxOptions } from "../syntax-theme";

interface OutputStep {
  line: number;
  trace: string;
  output?: string;
}

declare const data: { sourceHtml: string; steps: OutputStep[] };
export { data };

export default defineLoader({
  watch: [
    "../../public/examples/stdout-demo.ahk",
    "../syntax-theme.ts",
    "../ahk-language.json",
  ],
  async load() {
    const source = (
      await readFile(
        resolve(process.cwd(), "public/examples/stdout-demo.ahk"),
        "utf8",
      )
    ).trimEnd();
    const markdown = await createMarkdownRenderer(process.cwd(), syntaxOptions);
    const rendered = markdown.render(`\`\`\`ahk\n${source}\n\`\`\``);
    const sourceHtml = rendered.match(/<pre\b[\s\S]*?<\/pre>/)?.[0];
    if (!sourceHtml) throw new Error("Missing highlighted stdout example");

    // Playback of this repository-owned example, checked against the Console
    // executable by scripts/check-examples.py. No AHK runs in the browser.
    const outputByLine: Record<number, string> = {
      2: "Hello, terminal!",
      4: "Answer: 42",
      5: "Done.",
    };
    const steps = source
      .split(/\r?\n/)
      .slice(1)
      .map((statement, index) => {
        const line = index + 2;
        return {
          line,
          trace: `[trace] stdout-demo.ahk:${line}  ${statement}`,
          output: outputByLine[line],
        };
      });
    return {
      sourceHtml: sourceHtml.replace("<pre ", '<pre aria-label="Example source" '),
      steps,
    };
  },
});
