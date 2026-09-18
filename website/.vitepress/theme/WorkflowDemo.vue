<script setup>
import { ref, computed } from "vue";
const selected = ref(0);
const steps = [
  {
    name: "01 Write",
    label: "demo.ahk",
    code: '#Requires AutoHotkey v2.1-alpha.31\n#EnableEval\n\nconfig := JSON.Parse(\'{"count":21}\')\ncount := config["count"]\nPrint("answer={}", Eval("count * 2"))',
    output: "Write / Edit triggers ClautoHotkey’s post-edit validation.",
  },
  {
    name: "02 Validate",
    label: "ClautoHotkey hook",
    code: 'harness.env\n  AHK_BIN_WIN="C:\\Tools\\AutoHotkey64Console.exe"\n  AHK_DIAG_JSON=1\n  RUNTIME_PROBE=1\n\nahk-post-edit.sh → configured interpreter',
    output: "Syntax check first. Optional bounded runtime probe next.",
  },
  {
    name: "03 Execute",
    label: "PowerShell",
    code: "ahk /Headless /Diag=json demo.ahk\n\nanswer=42\n\n# stdout: result\n# stderr: diagnostics\n# exit code: 0",
    output:
      "Expected output for this example. Run it with a compatible local build.",
  },
  {
    name: "04 Inspect",
    label: "Local MCP client",
    code: '{\n  "name": "check",\n  "arguments": {\n    "file": "C:\\Scripts\\demo.ahk"\n  }\n}',
    output:
      "Check returns a parse verdict. Use test and assertions to verify behavior.",
  },
];
const current = computed(() => steps[selected.value]);
function move(event) {
  if (!["ArrowRight", "ArrowLeft", "Home", "End"].includes(event.key)) return;
  event.preventDefault();
  selected.value =
    event.key === "Home"
      ? 0
      : event.key === "End"
        ? 3
        : (selected.value + (event.key === "ArrowRight" ? 1 : 3)) % 4;
  event.currentTarget.querySelectorAll("button")[selected.value].focus();
}
</script>

<template>
  <div class="workflow-demo">
    <div
      role="tablist"
      aria-label="Explore the development workflow"
      class="workflow-tabs"
      @keydown="move"
    >
      <button
        v-for="(step, i) in steps"
        :key="step.name"
        role="tab"
        :id="`workflow-tab-${i}`"
        :aria-selected="selected === i"
        :tabindex="selected === i ? 0 : -1"
        aria-controls="workflow-panel"
        @click="selected = i"
      >
        {{ step.name }}
      </button>
    </div>
    <div
      id="workflow-panel"
      role="tabpanel"
      :aria-labelledby="`workflow-tab-${selected}`"
      tabindex="0"
    >
      <div class="terminal-label">
        <span class="terminal-dot"></span>{{ current.label
        }}<span>WALKTHROUGH</span>
      </div>
      <pre><code>{{ current.code }}</code></pre>
      <p class="terminal-note">{{ current.output }}</p>
    </div>
    <p class="demo-caption">
      Interactive walkthrough · code runs on your Windows machine, not in this
      browser.
    </p>
  </div>
</template>
