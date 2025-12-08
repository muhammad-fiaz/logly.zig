import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Logly.Zig',
  description: 'High-Performance Logging Library for Zig',
  base: '/logly.zig/',
  
  themeConfig: {
    logo: '/logo.svg',
    
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'API', link: '/api/logger' },
      { text: 'Examples', link: '/examples/basic' },
      { text: 'GitHub', link: 'https://github.com/muhammad-fiaz/logly.zig' }
    ],

    sidebar: [
      {
        text: 'Introduction',
        items: [
          { text: 'What is Logly?', link: '/guide/introduction' },
          { text: 'Getting Started', link: '/guide/getting-started' },
          { text: 'Quick Start', link: '/guide/quick-start' }
        ]
      },
      {
        text: 'Core Concepts',
        items: [
          { text: 'Log Levels', link: '/guide/log-levels' },
          { text: 'Configuration', link: '/guide/configuration' },
          { text: 'Colors & Styling', link: '/guide/colors' },
          { text: 'Sinks', link: '/guide/sinks' },
          { text: 'Formatting', link: '/guide/formatting' },
          { text: 'Custom Levels', link: '/guide/custom-levels' }
        ]
      },
      {
        text: 'Features',
        items: [
          { text: 'File Rotation', link: '/guide/rotation' },
          { text: 'JSON Logging', link: '/guide/json' },
          { text: 'Context Binding', link: '/guide/context' },
          { text: 'Callbacks', link: '/guide/callbacks' },
          { text: 'Async Logging', link: '/guide/async' },
          { text: 'Compression', link: '/guide/compression' },
          { text: 'Thread Pool', link: '/guide/thread-pool' },
          { text: 'Scheduler', link: '/guide/scheduler' },
          { text: 'System Diagnostics', link: '/guide/diagnostics' },
          { text: 'Source Location', link: '/guide/source-location' },
          { text: 'Arena Allocation', link: '/guide/arena-allocation' },
          { text: 'Update Checker', link: '/guide/update-checker' }
        ]
      },
      {
        text: 'Enterprise Features',
        items: [
          { text: 'Filtering', link: '/guide/filtering' },
          { text: 'Sampling', link: '/guide/sampling' },
          { text: 'Redaction', link: '/guide/redaction' },
          { text: 'Metrics', link: '/guide/metrics' },
          { text: 'Distributed Tracing', link: '/guide/tracing' },
          { text: 'Customizations', link: '/guide/customizations' }
        ]
      },
      {
        text: 'API Reference',
        items: [
          { text: 'Logger', link: '/api/logger' },
          { text: 'Config', link: '/api/config' },
          { text: 'Level', link: '/api/level' },
          { text: 'Sink', link: '/api/sink' },
          { text: 'Record', link: '/api/record' },
          { text: 'Async', link: '/api/async' },
          { text: 'Compression', link: '/api/compression' },
          { text: 'Thread Pool', link: '/api/thread-pool' },
          { text: 'Scheduler', link: '/api/scheduler' },
          { text: 'Diagnostics', link: '/api/diagnostics' },
          { text: 'Customizations', link: '/api/customizations' }
        ]
      },
      {
        text: 'Examples',
        items: [
          { text: 'Basic Usage', link: '/examples/basic' },
          { text: 'File Logging', link: '/examples/file-logging' },
          { text: 'Rotation', link: '/examples/rotation' },
          { text: 'JSON Logging', link: '/examples/json' },
          { text: 'Custom Colors', link: '/examples/custom-colors' },
          { text: 'Color Control', link: '/examples/color-control' },
          { text: 'Context', link: '/examples/context' },
          { text: 'Callbacks', link: '/examples/callbacks' },
          { text: 'Async Logging', link: '/examples/async-logging' },
          { text: 'Advanced Config', link: '/examples/advanced-config' },
          { text: 'Module Levels', link: '/examples/module-levels' },
          { text: 'Sink Formats', link: '/examples/sink-formats' },
          { text: 'Formatted Logging', link: '/examples/formatted-logging' },
          { text: 'Extended JSON', link: '/examples/json-extended' },
          { text: 'Time Formatting', link: '/examples/time' },
          { text: 'Filtering', link: '/examples/filtering' },
          { text: 'Sampling', link: '/examples/sampling' },
          { text: 'Redaction', link: '/examples/redaction' },
          { text: 'Metrics', link: '/examples/metrics' },
          { text: 'Tracing', link: '/examples/tracing' },
          { text: 'Production Config', link: '/examples/production-config' },
          { text: 'Diagnostics', link: '/examples/diagnostics' }
        ]
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/muhammad-fiaz/logly.zig' }
    ],

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2025 Muhammad Fiaz'
    },

    search: {
      provider: 'local'
    }
  }
})
