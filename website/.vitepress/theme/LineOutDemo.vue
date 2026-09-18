<script setup>
import { computed, onBeforeUnmount, ref } from "vue";
import { withBase } from "vitepress";
import { data } from "./stdout-demo.data";

const showTrace = ref(false);
const visibleSteps = ref(data.steps.length);
const playing = ref(false);
let timer;

const shown = computed(() => data.steps.slice(0, visibleSteps.value));
const stdout = computed(() =>
  shown.value.filter((step) => step.output !== undefined),
);
const trace = computed(() => shown.value.map((step) => step.trace).join("\n"));
const sourceHtml = computed(() => {
  const activeLine = playing.value ? shown.value.at(-1)?.line : undefined;
  let line = 0;
  return data.sourceHtml.replace(/<span class="line">/g, () => {
    line += 1;
    return `<span class="line${line === activeLine ? " is-executing" : ""}">`;
  });
});

function stop() {
  clearInterval(timer);
  playing.value = false;
}

function replay() {
  stop();
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    visibleSteps.value = data.steps.length;
    return;
  }
  visibleSteps.value = 0;
  playing.value = true;
  timer = window.setInterval(() => {
    if (visibleSteps.value === data.steps.length) stop();
    else visibleSteps.value += 1;
  }, 650);
}

onBeforeUnmount(stop);
</script>

<template>
  <div class="workflow-demo line-out-demo">
    <div class="line-out-demo-bar">
      <span
        ><span class="terminal-dot" aria-hidden="true"></span> PRINT →
        STDOUT</span
      >
      <button
        type="button"
        :aria-pressed="showTrace"
        aria-controls="line-out-demo-content"
        @click="showTrace = !showTrace"
      >
        {{ showTrace ? "Show script" : "Show trace" }}
      </button>
    </div>
    <div class="line-out-command">
      <span aria-hidden="true">›</span> ahk /Trace .\stdout-demo.ahk
    </div>
    <div id="line-out-demo-content" class="line-out-demo-content">
      <p class="line-out-output-label">
        {{
          showTrace ? "STDERR / EXECUTING STATEMENTS" : "SOURCE / stdout-demo.ahk"
        }}
      </p>
      <pre
        v-if="showTrace"
        class="line-out-trace"
        tabindex="0"
        aria-label="Example trace output"
      ><code>{{ trace || "Waiting for the first statement…" }}</code></pre>
      <div v-else class="line-out-source" v-html="sourceHtml"></div>
      <div class="line-out-result">
        <div class="line-out-result-bar">
          <span>STDOUT / PRINTED TEXT</span>
          <button type="button" :disabled="playing" @click="replay">
            {{ playing ? "Playing…" : "Replay output" }}
          </button>
        </div>
        <div
          class="stdout-output"
          role="log"
          aria-label="Standard output"
          aria-live="polite"
          aria-relevant="additions"
          tabindex="0"
        >
          <div v-for="step in stdout" :key="step.line">{{ step.output }}</div>
          <span v-if="!stdout.length" class="stdout-waiting"
            >Waiting for Print()…</span
          >
        </div>
      </div>
    </div>
    <p class="terminal-note">
      Each <code>Print()</code> writes a new line to stdout.
      <code>/Trace</code> sends executing statements to stderr.
    </p>
    <p class="demo-caption">
      Example playback · run
      <a :href="withBase('/examples/stdout-demo.ahk')" download>stdout-demo.ahk</a>
      locally to try it.
    </p>
  </div>
</template>
