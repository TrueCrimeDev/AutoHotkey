<script setup>
import { withBase } from "vitepress";
import ErrorFeedbackDemo from "./ErrorFeedbackDemo.vue";
import FeatureExplorer from "./FeatureExplorer.vue";
</script>

<template>
  <main class="product-home">
    <section class="hero-block" aria-labelledby="feedback-heading">
      <div class="hero-copy">
        <h1 id="feedback-heading">Errors your AI<br /><em>can act on.</em></h1>
        <p class="hero-description">
          Give Claude Code the error, the source line, and a way to check the
          fix. Console exposes AutoHotkey failures as structured diagnostics.
          ClautoHotkey brings that feedback into your editing workflow.
        </p>
        <div class="hero-actions">
          <a class="primary-action" :href="withBase('/guide/ai-feedback.html')"
            >See the error workflow <span aria-hidden="true">→</span></a
          >
          <a
            class="secondary-action"
            :href="withBase('/clautohotkey/setup.html')"
            >Set up ClautoHotkey <span aria-hidden="true">↗</span></a
          >
        </div>
        <p class="hero-meta">
          READ THE ERROR · CORRECT THE SOURCE · VERIFY THE RESULT
        </p>
      </div>
      <div class="hero-terminal"><ErrorFeedbackDemo /></div>
    </section>

    <div class="line-out-benefits" aria-label="Three core features">
      <div>
        <span class="benefit-number" aria-hidden="true">01</span>
        <div>
          <strong
            ><a :href="withBase('/guide/ai-feedback.html')"
              >Errors AI can read.</a
            ></strong
          >
          <p>
            Structured failures give Claude a specific problem to diagnose and
            repair.
          </p>
        </div>
      </div>
      <div>
        <span class="benefit-number" aria-hidden="true">02</span>
        <div>
          <strong
            ><a :href="withBase('/console/line-out.html')"
              >Trace what led there.</a
            ></strong
          >
          <p>
            Line Out shows which statements ran, with source files and line
            numbers.
          </p>
        </div>
      </div>
      <div>
        <span class="benefit-number" aria-hidden="true">03</span>
        <div>
          <strong
            ><a :href="withBase('/console/print-json.html')"
              >Print useful results.</a
            ></strong
          >
          <p>
            Send values and JSON to stdout for tools, pipelines, and assertions.
          </p>
        </div>
      </div>
    </div>

    <section
      class="home-section line-out-start"
      id="error-feedback"
      aria-labelledby="try-heading"
    >
      <div>
        <p class="eyebrow">THE FEEDBACK LOOP</p>
        <h2 id="try-heading">Give Claude the<br />missing context.</h2>
        <p>
          The error class explains what failed. The file, line, and source text
          show where to look. Claude can use those details to propose a focused
          edit, then read the next check or runtime result.
        </p>
        <a class="text-action" :href="withBase('/clautohotkey/workflow.html')"
          >Connect edits to checks <span aria-hidden="true">→</span></a
        >
      </div>
      <div class="line-out-quickstart">
        <p class="quickstart-label">1. Start with a real failure</p>
        <a
          class="example-download"
          :href="withBase('/examples/error-demo.ahk')"
          download
        >
          error-demo.ahk <span>Download the failing example ↓</span>
        </a>
        <p class="quickstart-label">2. Capture an error the AI can read</p>
        <pre
          tabindex="0"
          aria-label="Run the error feedback example"
        ><code>ahk /Headless /Diag=json .\error-demo.ahk</code></pre>
        <p class="quickstart-help">
          First time here?
          <a :href="withBase('/guide/installation.html')"
            >Build the Console executable</a
          >
          and
          <a
            :href="
              withBase(
                '/guide/installation.html#add-a-temporary-powershell-alias',
              )
            "
            >set up the ahk alias</a
          >.
        </p>
        <p class="line-out-limit">
          stderr carries the diagnostic; exit 10 signals this runtime failure.
          <a :href="withBase('/guide/ai-feedback.html')"
            >Read the diagnosis, correction, and verified rerun.</a
          >
        </p>
      </div>
    </section>

    <section
      class="home-section extras-section"
      id="extras"
      aria-labelledby="extras-heading"
    >
      <div class="section-heading">
        <div>
          <p class="eyebrow">CONSOLE + CLAUTOHOTKEY</p>
          <h2 id="extras-heading">Build the repair loop.</h2>
        </div>
        <p>Connect the interpreter, editor, and verification tools.</p>
      </div>
      <div class="extra-links">
        <a :href="withBase('/console/diagnostics.html')">
          <h3>Readable failures <span aria-hidden="true">↗</span></h3>
          <p>Error types, source locations, captured stderr, and exit codes.</p>
        </a>
        <a :href="withBase('/clautohotkey/setup.html')">
          <h3>Claude Code feedback <span aria-hidden="true">↗</span></h3>
          <p>
            ClautoHotkey hooks check edits; local MCP tools expose results to
            the AI.
          </p>
        </a>
        <a :href="withBase('/recipes/testing-ci.html')">
          <h3>Checks & tests <span aria-hidden="true">↗</span></h3>
          <p>Syntax checks, runtime assertions, and coverage.</p>
        </a>
      </div>
      <details class="extras-details">
        <summary>Explore the full toolkit</summary>
        <FeatureExplorer />
      </details>
      <p class="extras-evidence">
        Want to inspect a complete workflow?
        <a :href="withBase('/showcase.html')">See the real session gallery →</a>
      </p>
    </section>
    <div class="home-version">
      <span>DEVELOPMENT REFERENCE</span>
      <p>
        The error demonstration was recorded with alpha.31 +Console and Claude
        Code. Check your executable’s capabilities before using development
        features.
      </p>
      <a :href="withBase('/guide/compatibility.html')">Build compatibility →</a>
    </div>
  </main>
</template>
