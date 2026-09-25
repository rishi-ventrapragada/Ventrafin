<script setup lang="ts">
// The Ventrafin mark (same drawing as public/favicon.svg).
withDefaults(defineProps<{ size?: number }>(), { size: 28 })
</script>

<template>
  <svg :width="size" :height="size" viewBox="0 0 64 64" aria-hidden="true" class="shrink-0">
    <rect width="64" height="64" rx="14" fill="#1565C0" />
    <path d="M16 18h8l8 22 8-22h8L36 48h-8z" fill="#fff" />
    <circle cx="48" cy="46" r="5" fill="#26A69A" />
  </svg>
</template>
