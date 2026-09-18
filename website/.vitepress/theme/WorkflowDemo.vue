<script setup>
import { ref, computed } from "vue";
import { data as steps } from "./workflow.data";
const selected = ref(0);

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
      <div class="workflow-code" v-html="current.html"></div>
      <p class="terminal-note">{{ current.output }}</p>
    </div>
    <p class="demo-caption">
      Interactive walkthrough · code runs on your Windows machine, not in this
      browser.
    </p>
  </div>
</template>
