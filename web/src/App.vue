<script setup lang="ts">
import ConfirmDialog from 'primevue/confirmdialog'
import Toast from 'primevue/toast'
import { RouterView } from 'vue-router'
</script>

<template>
  <RouterView />
  <Toast position="bottom-right" />
  <ConfirmDialog :style="{ width: '28rem' }" />
</template>
