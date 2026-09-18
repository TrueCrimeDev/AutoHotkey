<script setup>
import { computed, ref } from "vue";
import { withBase } from "vitepress";
import { features } from "./features";
const filter = ref("All");
const groups = ["All", "Console", "ClautoHotkey", "Together"];
const shown = computed(() =>
  features.filter((f) => filter.value === "All" || f.group === filter.value),
);
</script>

<template>
  <div class="explorer">
    <div class="feature-filters" aria-label="Filter features">
      <button
        v-for="group in groups"
        :key="group"
        :data-group="group"
        :aria-pressed="filter === group"
        @click="filter = group"
      >
        {{ group }}
      </button>
      <span aria-live="polite">{{ shown.length }} features</span>
    </div>
    <div class="feature-grid">
      <a
        v-for="(feature, index) in shown"
        :key="feature.title"
        class="feature-card"
        :data-group="feature.group"
        :href="withBase(feature.path + '.html')"
      >
        <div class="feature-card-top">
          <span>{{ feature.tag }}</span
          ><span aria-hidden="true">↗</span>
        </div>
        <h3>{{ feature.title }}</h3>
        <p>{{ feature.description }}</p>
        <span class="feature-family"
          >{{ feature.group }} <span aria-hidden="true">/</span> Read the
          guide</span
        >
      </a>
    </div>
  </div>
</template>
