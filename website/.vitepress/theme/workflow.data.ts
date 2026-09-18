import { createMarkdownRenderer, defineLoader } from "vitepress";
import { syntaxOptions } from "../syntax-theme";
import { steps } from "./workflow-steps";

declare const data: Array<(typeof steps)[number] & { html: string }>;
export { data };

export default defineLoader({
  watch: ["./workflow-steps.ts", "../syntax-theme.ts", "../ahk-language.json"],
  async load() {
    const markdown = await createMarkdownRenderer(process.cwd(), syntaxOptions);
    return steps.map((step) => {
      // Only repository-owned snippets are rendered. Highlight at build time so
      // switching tabs never downloads a highlighter or inserts untrusted HTML.
      const rendered = markdown.render(
        `\`\`\`${step.language}\n${step.code}\n\`\`\``,
      );
      const html = rendered.match(/<pre\b[\s\S]*?<\/pre>/)?.[0];
      if (!html)
        throw new Error(`Missing highlighted workflow step: ${step.name}`);
      return { ...step, html };
    });
  },
});
