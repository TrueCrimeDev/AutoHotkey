<script setup>
import { withBase } from "vitepress";
import WorkflowDemo from "./WorkflowDemo.vue";
import FeatureExplorer from "./FeatureExplorer.vue";
</script>

<template>
  <main class="product-home">
    <section class="hero-block">
      <div class="hero-copy">
        <div class="eyebrow">
          <span></span> AUTOHOTKEY V2, WITH A FEEDBACK LOOP
        </div>
        <h1>
          Your scripts.<br />Your terminal.<br /><em>Working together.</em>
        </h1>
        <p class="hero-description">
          Console gives AutoHotkey a voice in your terminal. ClautoHotkey gives
          Claude Code the tools to listen, check, and iterate.
        </p>
        <div class="hero-actions">
          <a class="primary-action" :href="withBase('/guide/quick-start.html')"
            >Start building <span aria-hidden="true">→</span></a
          >
          <a class="secondary-action" :href="withBase('/showcase.html')"
            >See a real session <span aria-hidden="true">↗</span></a
          >
        </div>
        <p class="hero-meta">WINDOWS · OPEN SOURCE · LOCAL TOOLS</p>
      </div>
      <div class="hero-terminal"><WorkflowDemo /></div>
    </section>

    <div class="project-strip">
      <div>
        <span class="project-icon" aria-hidden="true">&gt;_</span>
        <div>
          <strong>AutoHotkey Console</strong>
          <p>The engine. Output, diagnostics, testing, and inspection.</p>
        </div>
      </div>
      <span class="join-mark" aria-hidden="true">+</span>
      <div>
        <span class="project-icon harness-icon" aria-hidden="true">⌘</span>
        <div>
          <strong>ClautoHotkey</strong>
          <p>The workflow. Claude Code hooks, skills, and grading gates.</p>
        </div>
      </div>
    </div>

    <section class="home-section" id="explore">
      <div class="section-heading">
        <div>
          <p class="eyebrow">THE TOOLKIT</p>
          <h2>Go beyond “the script ran.”</h2>
        </div>
        <p>Understand what happened.<br />Then take the next useful step.</p>
      </div>
      <FeatureExplorer />
    </section>

    <section class="evidence-section">
      <div>
        <p class="eyebrow">FROM AN ACTUAL CLAUDE CODE SESSION</p>
        <h2>A workflow you<br />can inspect.</h2>
        <p>
          Real edits, real hooks, real engine calls. The demo gallery includes
          screenshots, downloadable scripts, test outcomes, and the limits of
          each check.
        </p>
        <a class="text-action" :href="withBase('/showcase.html')"
          >Explore the evidence <span aria-hidden="true">→</span></a
        >
      </div>
      <div class="evidence-results">
        <div>
          <strong>26 / 26</strong><span>Runtime assertions passed</span>
        </div>
        <div><strong>174</strong><span>Valid JSON trace records</span></div>
        <div><strong>77 / 84</strong><span>Instrumented lines hit</span></div>
        <p>
          September 17, 2026 · development build<br />Static parse: partial. Raw
          dry-run output: checker issue recorded.
        </p>
      </div>
    </section>

    <section class="home-section paths-section">
      <p class="eyebrow">PICK YOUR NEXT STEP</p>
      <h2>Start small. Keep the signal.</h2>
      <div class="learning-paths">
        <a :href="withBase('/guide/quick-start.html')"
          ><span>01 / FIRST RUN</span>
          <h3>From script to terminal</h3>
          <p>
            Identify your engine, write a small script, and separate results
            from errors.
          </p>
          <b>Quick start →</b></a
        >
        <a :href="withBase('/clautohotkey/setup.html')"
          ><span>02 / YOUR EDITOR</span>
          <h3>Bring Claude into the loop</h3>
          <p>
            Install the plugin, point it at your engine, and verify an actual
            post-edit hook.
          </p>
          <b>Set up ClautoHotkey →</b></a
        >
        <a :href="withBase('/recipes/testing-ci.html')"
          ><span>03 / REPEATABLE RESULTS</span>
          <h3>Turn checks into a habit</h3>
          <p>
            Add behavioral assertions, coverage, and a Windows CI job that
            records failures.
          </p>
          <b>Build a test workflow →</b></a
        >
      </div>
    </section>
    <div class="home-version">
      <span>DEVELOPMENT REFERENCE</span>
      <p>
        Examples target the demonstrated alpha.31 +Console build. Check your
        executable’s capabilities before using newer features.
      </p>
      <a :href="withBase('/guide/compatibility.html')">Build compatibility →</a>
    </div>
  </main>
</template>
