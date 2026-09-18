import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createMarkdownRenderer, defineLoader } from "vitepress";
import { syntaxOptions } from "../syntax-theme";
import evidence from "../../public/examples/ai-error-feedback.json";

declare const data: {
  evidence: typeof evidence;
  sourceHtml: string;
  fixedHtml: string;
  diagnosticHtml: string;
};
export { data };

export default defineLoader({
  watch: [
    "../../public/examples/error-demo*.ahk",
    "../../public/examples/ai-error-feedback.json",
    "../syntax-theme.ts",
    "../ahk-language.json",
  ],
  async load() {
    const markdown = await createMarkdownRenderer(process.cwd(), syntaxOptions);
    const highlight = (source: string, language: string, label: string) => {
      const html = markdown
        .render(`\`\`\`${language}\n${source.trimEnd()}\n\`\`\``)
        .match(/<pre\b[\s\S]*?<\/pre>/)?.[0];
      if (!html) throw new Error(`Missing highlighted ${label}`);
      return html.replace("<pre ", `<pre aria-label="${label}" `);
    };
    const source = await readFile(
      resolve(process.cwd(), "public/examples/error-demo.ahk"),
      "utf8",
    );
    const fixed = await readFile(
      resolve(process.cwd(), "public/examples/error-demo-fixed.ahk"),
      "utf8",
    );
    const {
      type,
      message,
      extra,
      file,
      line,
      source: statement,
    } = evidence.failedRun.diagnostic;
    return {
      evidence,
      sourceHtml: highlight(source, "ahk", "Failing script"),
      fixedHtml: highlight(fixed, "ahk", "Corrected script"),
      diagnosticHtml: highlight(
        JSON.stringify(
          { type, message, extra, file, line, source: statement },
          null,
          2,
        ),
        "json",
        "Captured JSON error",
      ),
    };
  },
});
