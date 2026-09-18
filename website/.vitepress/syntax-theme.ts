import type { MarkdownOptions } from "vitepress";
import ahk from "./ahk-language.json";

// Match the AHKv2 & LLMs reference site's VS Code Dark+ token palette:
// https://truecrimedev.github.io/AHKv2_LLMs/post.html?slug=tapholdmanager
export const syntaxOptions: MarkdownOptions = {
  languages: [ahk],
  theme: {
    name: "ahk-dark-plus",
    type: "dark",
    colors: { "editor.background": "#171717", "editor.foreground": "#9cdcfe" },
    tokenColors: [
      {
        scope: ["comment", "punctuation.definition.comment"],
        settings: { foreground: "#6a9955", fontStyle: "italic" },
      },
      {
        scope: [
          "string",
          "constant.character.escape",
          "punctuation.definition.string",
        ],
        settings: { foreground: "#ce9178" },
      },
      { scope: ["constant.numeric"], settings: { foreground: "#b5cea8" } },
      {
        scope: ["keyword", "storage", "constant.language"],
        settings: { foreground: "#569cd6" },
      },
      {
        scope: ["entity.name.type", "support.type", "storage.type"],
        settings: { foreground: "#4ec9b0" },
      },
      {
        scope: ["entity.name.function", "support.function", "entity.name.tag"],
        settings: { foreground: "#dcdcaa" },
      },
      {
        scope: ["variable", "support.variable", "meta.object-literal.key"],
        settings: { foreground: "#9cdcfe" },
      },
      {
        scope: ["keyword.operator", "punctuation"],
        settings: { foreground: "#d4d4d4" },
      },
      {
        scope: ["keyword.control.directive", "meta.preprocessor"],
        settings: { foreground: "#c586c0" },
      },
    ],
  },
};
