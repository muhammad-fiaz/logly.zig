<script setup lang="ts">
import DefaultLayout from 'vitepress/theme/Layout.vue'
import Breadcrumbs from './Breadcrumbs.vue'
</script>

<template>
  <DefaultLayout>
    <template #doc-before>
      <Breadcrumbs />
    </template>
  </DefaultLayout>
</template>
