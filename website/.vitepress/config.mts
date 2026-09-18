import { defineConfig } from "vitepress";
import ahk from "./ahk-language.json";

// VitePress must treat AHK downloads as files in both build-time and client routing.
process.env.VITE_EXTRA_EXTENSIONS = "ahk";

export default defineConfig({
  title: "Console + ClautoHotkey",
  description:
    "AutoHotkey for the terminal. A development workflow for Claude Code. Explore the Console fork and ClautoHotkey together.",
  base: "/AutoHotkey/",
  cleanUrls: false,
  lastUpdated: true,
  sitemap: { hostname: "https://truecrimedev.github.io/AutoHotkey/" },
  head: [
    [
      "link",
      {
        rel: "icon",
        type: "image/png",
        href: "/AutoHotkey/images/autohotkey-logo.png",
      },
    ],
    [
      "link",
      {
        rel: "apple-touch-icon",
        href: "/AutoHotkey/images/autohotkey-logo.png",
      },
    ],
    [
      "meta",
      {
        name: "theme-color",
        content: "#fafbf8",
        media: "(prefers-color-scheme: light)",
      },
    ],
    [
      "meta",
      {
        name: "theme-color",
        content: "#191919",
        media: "(prefers-color-scheme: dark)",
      },
    ],
    ["meta", { property: "og:type", content: "website" }],
    ["meta", { property: "og:site_name", content: "Console + ClautoHotkey" }],
  ],
  markdown: { lineNumbers: true, languages: [ahk] },
  vite: {
    define: { "import.meta.env.VITE_EXTRA_EXTENSIONS": JSON.stringify("ahk") },
  },
  themeConfig: {
    logo: { src: "/images/autohotkey-logo.png", alt: "AutoHotkey logo" },
    siteTitle: "Console + ClautoHotkey",
    nav: [
      {
        text: "Start here",
        link: "/guide/quick-start",
        activeMatch: "/guide/",
      },
      { text: "Console", link: "/console/overview", activeMatch: "/console/" },
      {
        text: "ClautoHotkey",
        link: "/clautohotkey/setup",
        activeMatch: "/clautohotkey/",
      },
      { text: "Recipes", link: "/recipes/", activeMatch: "/recipes/" },
      { text: "Showcase", link: "/showcase", activeMatch: "/showcase" },
    ],
    sidebar: [
      {
        text: "GET STARTED",
        items: [
          { text: "The two projects", link: "/guide/overview" },
          { text: "Quick start", link: "/guide/quick-start" },
          { text: "Build & install", link: "/guide/installation" },
          { text: "Versions & availability", link: "/guide/compatibility" },
        ],
      },
      {
        text: "CONSOLE ENGINE",
        collapsed: false,
        items: [
          { text: "Feature explorer", link: "/console/overview" },
          { text: "CLI & PowerShell", link: "/console/cli" },
          { text: "Structured diagnostics", link: "/console/diagnostics" },
          { text: "Print & native JSON", link: "/console/print-json" },
          { text: "Eval & the REPL", link: "/console/eval-repl" },
          { text: "Inspect & Check", link: "/console/inspect-check" },
          { text: "Child process pipes", link: "/console/process-pipe" },
          { text: "Trace & coverage", link: "/console/trace-coverage" },
          { text: "Crash logs & source context", link: "/console/crash-logs" },
        ],
      },
      {
        text: "CLAUTOHOTKEY",
        collapsed: false,
        items: [
          { text: "Plugin setup", link: "/clautohotkey/setup" },
          { text: "The edit → verify loop", link: "/clautohotkey/workflow" },
          { text: "Skills, rules & knowledge", link: "/clautohotkey/skills" },
          { text: "Static & dry-run gates", link: "/clautohotkey/harness" },
          { text: "MCP integration", link: "/clautohotkey/mcp" },
        ],
      },
      {
        text: "BUILD SOMETHING",
        collapsed: false,
        items: [
          { text: "Recipe library", link: "/recipes/" },
          { text: "A JSON command-line tool", link: "/recipes/json-cli" },
          { text: "A validated Claude edit", link: "/recipes/validated-edit" },
          { text: "Tests & Windows CI", link: "/recipes/testing-ci" },
          { text: "A process worker", link: "/recipes/process-worker" },
          { text: "Real session gallery", link: "/showcase" },
        ],
      },
      {
        text: "REFERENCE",
        collapsed: true,
        items: [
          { text: "Command & exit-code tables", link: "/reference/commands" },
          { text: "Troubleshooting", link: "/reference/troubleshooting" },
          { text: "Verification & sources", link: "/reference/verification" },
          { text: "Contribute to these docs", link: "/reference/contributing" },
        ],
      },
    ],
    search: { provider: "local", options: { detailedView: true } },
    outline: { level: [2, 3], label: "On this page" },
    socialLinks: [
      { icon: "github", link: "https://github.com/TrueCrimeDev/AutoHotkey" },
    ],
    editLink: {
      pattern:
        "https://github.com/TrueCrimeDev/AutoHotkey/edit/alpha/website/:path",
      text: "Improve this page on GitHub",
    },
    footer: {
      message:
        "AutoHotkey Console × ClautoHotkey · Independent projects built on AutoHotkey v2.",
      copyright:
        "Engine: GPL-2.0 · ClautoHotkey: MIT · Examples reflect the stated build.",
    },
  },
});
