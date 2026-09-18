<script setup>
import { withBase } from "vitepress";
import LineOutDemo from "./LineOutDemo.vue";
import FeatureExplorer from "./FeatureExplorer.vue";
</script>

<template>
  <main class="product-home">
    <section class="hero-block" aria-labelledby="line-out-heading">
      <div class="hero-copy">
        <div class="hero-brand">
          <img
            class="hero-logo"
            :src="withBase('/images/autohotkey-logo.png')"
            alt="AutoHotkey logo"
            width="56"
            height="56"
          />
          <div class="eyebrow">AUTOHOTKEY CONSOLE · LINE OUT</div>
        </div>
        <h1 id="line-out-heading">
          See your script.<br /><em>Line by line.</em>
        </h1>
        <p class="hero-description">
          Follow your AutoHotkey script as it runs. Line Out streams executing
          statements straight to your terminal, with the filename and line
          number. Just add <code>/Trace</code>.
        </p>
        <div class="hero-actions">
          <a class="primary-action" :href="withBase('/console/line-out.html')"
            >Get started with Line Out <span aria-hidden="true">→</span></a
          >
          <a class="secondary-action" href="#try-line-out"
            >Try the example <span aria-hidden="true">↓</span></a
          >
        </div>
        <p class="hero-meta">
          WINDOWS · OPEN SOURCE · BUILT INTO THE CONSOLE FORK
        </p>
      </div>
      <div class="hero-terminal"><LineOutDemo /></div>
    </section>

    <div class="line-out-benefits" aria-label="Line Out highlights">
      <div>
        <span class="benefit-number" aria-hidden="true">01</span>
        <div>
          <strong>Know which line ran.</strong>
          <p>Source location and statement text, together.</p>
        </div>
      </div>
      <div>
        <span class="benefit-number" aria-hidden="true">02</span>
        <div>
          <strong>Follow the actual path.</strong>
          <p>Watch branches, loops, and handlers execute.</p>
        </div>
      </div>
      <div>
        <span class="benefit-number" aria-hidden="true">03</span>
        <div>
          <strong>Quiet when your script is.</strong>
          <p>Idle scripts produce no new trace entries.</p>
        </div>
      </div>
    </div>

    <section
      class="home-section line-out-start"
      id="try-line-out"
      aria-labelledby="try-heading"
    >
      <div>
        <p class="eyebrow">START WITH LINE OUT</p>
        <h2 id="try-heading">One flag.<br />A clearer picture.</h2>
        <p>
          Add <code>/Trace</code> when you launch your script. No logging calls
          to scatter through your code. Keep the output in view, or save the
          trace for a closer look.
        </p>
        <a class="text-action" :href="withBase('/console/line-out.html')"
          >Read the Line Out guide <span aria-hidden="true">→</span></a
        >
      </div>
      <div class="line-out-quickstart">
        <p class="quickstart-label">1. Get the example</p>
        <a
          class="example-download"
          :href="withBase('/examples/line-out.ahk')"
          download
        >
          line-out.ahk <span>Download the four-line script ↓</span>
        </a>
        <p class="quickstart-label">2. Run it in PowerShell</p>
        <pre
          tabindex="0"
          aria-label="Run the Line Out example"
        ><code>ahk /Trace .\line-out.ahk</code></pre>
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
          A trace shows a statement starting. Use results and assertions to
          check whether it completed correctly.
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
          <p class="eyebrow">ALSO INCLUDED</p>
          <h2 id="extras-heading">A few extras, when you need them.</h2>
        </div>
        <p>More tools to support your scripts.</p>
      </div>
      <div class="extra-links">
        <a :href="withBase('/console/overview.html')">
          <h3>Console tools <span aria-hidden="true">↗</span></h3>
          <p>Print, JSON, a REPL, and structured diagnostics.</p>
        </a>
        <a :href="withBase('/clautohotkey/setup.html')">
          <h3>ClautoHotkey <span aria-hidden="true">↗</span></h3>
          <p>Optional Claude Code hooks, skills, and local MCP tools.</p>
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
        The Line Out example targets alpha.30 +Console or newer. Check your
        executable’s capabilities before using other development features.
      </p>
      <a :href="withBase('/guide/compatibility.html')">Build compatibility →</a>
    </div>
  </main>
</template>
