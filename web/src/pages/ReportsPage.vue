<script setup lang="ts">
import { RouterLink } from 'vue-router'
import ComingSoon from '@/components/ComingSoon.vue'
</script>

<template>
  <div class="flex flex-col gap-3">
    <ComingSoon
      title="Reports"
      icon="bar_chart"
      note="Month-by-month tables and charts arrive in phase 5. This month against last month, by category, is already on the Dashboard."
    />
    <RouterLink to="/dashboard" class="text-sm font-medium text-ocean hover:underline">Open the Dashboard</RouterLink>
  </div>
</template>
