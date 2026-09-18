<script setup>
import { ref } from "vue";
import { withBase } from "vitepress";
import { data } from "./error-feedback.data";

const selected = ref(0);
const tabs = ["01 Error", "02 Claude reads", "03 Fix verified"];
const { evidence } = data;
function move(event) {
  if (!["ArrowRight", "ArrowLeft", "Home", "End"].includes(event.key)) return;
  event.preventDefault();
  selected.value =
    event.key === "Home"
      ? 0
      : event.key === "End"
        ? 2
        : (selected.value + (event.key === "ArrowRight" ? 1 : 2)) % 3;
  event.currentTarget.querySelectorAll("button")[selected.value].focus();
}
</script>

<template>
  <div class="workflow-demo feedback-demo">
    <div class="feedback-bar">
      <span>ERROR → AI → VERIFIED FIX</span>
      <span :class="['feedback-status', { 'is-error': selected === 0 }]">
        {{
          selected === 0
            ? `EXIT ${evidence.failedRun.exitCode}`
            : selected === 1
              ? "CLAUDE CODE"
              : "EXIT 0"
        }}
      </span>
    </div>
    <div
      class="workflow-tabs feedback-tabs"
      role="tablist"
      aria-label="Explore AI error feedback"
      @keydown="move"
    >
      <button
        v-for="(name, index) in tabs"
        :key="name"
        type="button"
        :id="`feedback-tab-${index}`"
        role="tab"
        :aria-selected="selected === index"
        :tabindex="selected === index ? 0 : -1"
        aria-controls="feedback-panel"
        @click="selected = index"
      >
        {{ name }}
      </button>
    </div>
    <div
      id="feedback-panel"
      role="tabpanel"
      :aria-labelledby="`feedback-tab-${selected}`"
      tabindex="0"
    >
      <div v-if="selected === 0">
        <div class="line-out-command feedback-command">
          ahk /Headless /Diag=json .\error-demo.ahk
        </div>
        <div class="feedback-section">
          <p class="feedback-label">SOURCE / ERROR-DEMO.AHK · LINE 4</p>
          <div
            class="feedback-code feedback-failing"
            v-html="data.sourceHtml"
          ></div>
        </div>
        <div class="feedback-section">
          <p class="feedback-label">STDERR / JSON ERROR · SELECTED FIELDS</p>
          <div class="feedback-code" v-html="data.diagnosticHtml"></div>
        </div>
        <p class="feedback-explanation">
          The error reaches the calling tool with its type, source file, line,
          and failing statement.
        </p>
      </div>
      <div v-else-if="selected === 1" class="feedback-reading">
        <div class="feedback-section">
          <p class="feedback-label">CLAUDE CODE / RECORDED RESPONSE</p>
          <blockquote>{{ evidence.claude.diagnosis }}</blockquote>
          <dl class="feedback-location">
            <div>
              <dt>File</dt>
              <dd>{{ evidence.claude.file }}</dd>
            </div>
            <div>
              <dt>Line</dt>
              <dd>{{ evidence.claude.line }}</dd>
            </div>
          </dl>
        </div>
        <div class="feedback-section">
          <p class="feedback-label">CLAUDE'S PROPOSED CORRECTION</p>
          <div
            class="feedback-diff"
            tabindex="0"
            aria-label="Proposed line replacement"
          >
            <div>
              <span class="diff-label">Before</span
              ><code>{{ evidence.claude.original }}</code>
            </div>
            <div>
              <span class="diff-label">After</span
              ><code>{{ evidence.claude.replacement }}</code>
            </div>
          </div>
        </div>
        <p class="feedback-explanation">
          Claude received the script and captured diagnostic. It returned this
          replacement; the next step checks it.
        </p>
      </div>
      <div v-else>
        <div class="line-out-command feedback-command">
          ahk /Headless /Diag=json .\error-demo-fixed.ahk
        </div>
        <div class="feedback-section">
          <p class="feedback-label">SOURCE / CORRECTION APPLIED</p>
          <div
            class="feedback-code feedback-fixed"
            v-html="data.fixedHtml"
          ></div>
        </div>
        <div class="feedback-section">
          <p class="feedback-label">CONSOLE / RECORDED VERIFICATION</p>
          <dl class="feedback-verification">
            <div>
              <dt>Syntax check</dt>
              <dd>PASS · exit {{ evidence.verification.checkExitCode }}</dd>
            </div>
            <div>
              <dt>Runtime rerun</dt>
              <dd>PASS · exit {{ evidence.verification.runExitCode }}</dd>
            </div>
            <div>
              <dt>stderr</dt>
              <dd>Empty · no error</dd>
            </div>
            <div>
              <dt>Assertion</dt>
              <dd>{{ evidence.verification.assertion }} · PASS</dd>
            </div>
          </dl>
        </div>
        <p class="feedback-explanation">
          The corrected script ran successfully. A separate runtime assertion
          checked the resulting value.
        </p>
      </div>
    </div>
    <div class="feedback-controls">
      <span>{{ selected + 1 }} / 3</span>
      <button type="button" @click="selected = (selected + 1) % 3">
        {{
          [
            "See what Claude reads →",
            "Verify the correction →",
            "Back to the error ↺",
          ][selected]
        }}
      </button>
    </div>
    <p class="demo-caption">
      Recorded Console + Claude Code example ·
      <a :href="withBase('/guide/ai-feedback.html#how-this-demo-was-verified')"
        >How it was verified</a
      >
    </p>
  </div>
</template>
