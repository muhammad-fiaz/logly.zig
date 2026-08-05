<script setup lang="ts">
import { useData, useRoute } from 'vitepress'
import { computed } from 'vue'

const { page } = useData()
const route = useRoute()

const breadcrumbs = computed(() => {
  const path = route.path.replace(/\.html$/, '').replace(/\/index$/, '')
  const parts = path.split('/').filter(Boolean)
  
  const items: Array<{ label: string; link: string }> = []
  let currentPath = ''
  
  for (let i = 0; i < parts.length; i++) {
    currentPath += '/' + parts[i]
    const isLast = i === parts.length - 1
    const label = parts[i]
      .split('-')
      .map(s => s.charAt(0).toUpperCase() + s.slice(1))
      .join(' ')
    
    items.push({
      label,
      link: isLast ? '' : currentPath + '.html',
    })
  }
  
  return items
})
</script>

<template>
  <nav v-if="breadcrumbs.length > 1" class="breadcrumbs" aria-label="Breadcrumb">
    <ol>
      <li>
        <a href="/logly.zig/">Home</a>
      </li>
      <li v-for="(crumb, index) in breadcrumbs" :key="index">
        <span v-if="crumb.link" class="separator">/</span>
        <a v-if="crumb.link" :href="'/logly.zig' + crumb.link">{{ crumb.label }}</a>
        <span v-else class="current">{{ crumb.label }}</span>
      </li>
    </ol>
  </nav>
</template>

<style scoped>
.breadcrumbs {
  margin-bottom: 1rem;
  font-size: 0.875rem;
  color: var(--vp-c-text-2);
}

.breadcrumbs ol {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.25rem;
}

.breadcrumbs li {
  display: inline-flex;
  align-items: center;
}

.breadcrumbs .separator {
  margin: 0 0.25rem;
  color: var(--vp-c-text-3);
}

.breadcrumbs a {
  color: var(--vp-c-brand-1);
  text-decoration: none;
  transition: color 0.2s;
}

.breadcrumbs a:hover {
  color: var(--vp-c-brand-2);
  text-decoration: underline;
}

.breadcrumbs .current {
  color: var(--vp-c-text-1);
  font-weight: 500;
}
</style>
