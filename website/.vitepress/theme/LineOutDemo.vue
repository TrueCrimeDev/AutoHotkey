<script setup>
import { ref } from "vue";

const showSource = ref(false);
const trace =
  "[trace] line-out.ahk:2  value := 40\n[trace] line-out.ahk:3  value += 2\n[trace] line-out.ahk:4  Print(value)";
const source =
  "#Requires AutoHotkey v2.1-alpha.30\nvalue := 40\nvalue += 2\nPrint(value)";
</script>

<template>
  <div class="workflow-demo line-out-demo">
    <div class="line-out-demo-bar">
      <span
        ><span class="terminal-dot" aria-hidden="true"></span> LINE OUT /
        TRACE</span
      >
      <button
        type="button"
        :aria-pressed="showSource"
        aria-controls="line-out-demo-content"
        @click="showSource = !showSource"
      >
        Show script
      </button>
    </div>
    <div class="line-out-command">
      <span aria-hidden="true">›</span> ahk /Trace .\line-out.ahk
    </div>
    <div id="line-out-demo-content" class="line-out-demo-content">
      <p class="line-out-output-label">
        {{
          showSource ? "SOURCE / line-out.ahk" : "STDERR / EXECUTING STATEMENTS"
        }}
      </p>
      <pre
        tabindex="0"
        :aria-label="showSource ? 'Example source' : 'Example trace output'"
      ><code>{{ showSource ? source : trace }}</code></pre>
      <div class="line-out-result">
        <span>STDOUT / RESULT</span><strong>42</strong>
      </div>
    </div>
    <p class="terminal-note">
      Filename. Line number. The statement that just started.
    </p>
    <p class="demo-caption">
      Example output · run the script locally to see Line Out in action.
    </p>
  </div>
</template>
