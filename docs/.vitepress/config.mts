import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Logly.Zig',
  description: 'High-Performance Logging Library for Zig',
  base: '/logly.zig/',
  ignoreDeadLinks: [
    // Allow links to source files outside docs directory
    /.*\.zig$/
  ],
  
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
        text: 'Core Features',
        items: [
          { text: 'File Rotation', link: '/guide/rotation' },
          { text: 'JSON Logging', link: '/guide/json' },
          { text: 'Context Binding', link: '/guide/context' },
          { text: 'Callbacks', link: '/guide/callbacks' },
          { text: 'Source Location', link: '/guide/source-location' },
          { text: 'Stack Traces', link: '/guide/stack-traces' }
        ]
      },
      {
        text: 'Advanced Features',
        items: [
          { text: 'Async Logging', link: '/guide/async' },
          { text: 'Compression', link: '/guide/compression' },
          { text: 'Thread Pool', link: '/guide/thread-pool' },
          { text: 'Scheduler', link: '/guide/scheduler' },
          { text: 'Arena Allocation', link: '/guide/arena-allocation' },
          { text: 'Network Logging', link: '/guide/network-logging' }
        ]
      },
      {
        text: 'System & Operations',
        items: [
          { text: 'System Diagnostics', link: '/guide/diagnostics' },
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
          { text: 'Formatter', link: '/api/formatter' },
          { text: 'Rotation', link: '/api/rotation' },
          { text: 'Filter', link: '/api/filter' },
          { text: 'Sampler', link: '/api/sampler' },
          { text: 'Redactor', link: '/api/redactor' },
          { text: 'Metrics', link: '/api/metrics' },
          { text: 'Network', link: '/api/network' },
          { text: 'Update Checker', link: '/api/update-checker' },
          { text: 'Record', link: '/api/record' },
          { text: 'Async Queue', link: '/api/async' },
          { text: 'Compression', link: '/api/compression' },
          { text: 'Thread Pool', link: '/api/thread-pool' },
          { text: 'Scheduler', link: '/api/scheduler' },
          { text: 'Diagnostics', link: '/api/diagnostics' },
          { text: 'Customizations', link: '/api/customizations' }
        ]
      },
      {
        text: 'Code Examples',
        items: [
          { text: 'Basic Usage', link: '/examples/basic' },
          { text: 'File Logging', link: '/examples/file-logging' },
          { text: 'Rotation', link: '/examples/rotation' },
          { text: 'JSON Logging', link: '/examples/json' },
          { text: 'JSON Extended', link: '/examples/json-extended' },
          { text: 'Custom Colors', link: '/examples/custom-colors' },
          { text: 'Custom Theme', link: '/examples/custom-theme' },
          { text: 'Color Control', link: '/examples/color-control' },
          { text: 'Context', link: '/examples/context' },
          { text: 'Callbacks', link: '/examples/callbacks' },
          { text: 'Async Logging', link: '/examples/async-logging' },
          { text: 'Network Logging', link: '/examples/network-logging' },
          { text: 'Advanced Config', link: '/examples/advanced-config' },
          { text: 'Module Levels', link: '/examples/module-levels' },
          { text: 'Custom Levels Full', link: '/examples/custom-levels-full' },
          { text: 'Sink Formats', link: '/examples/sink-formats' },
          { text: 'Formatted Logging', link: '/examples/formatted-logging' },
          { text: 'Time Formatting', link: '/examples/time' },
          { text: 'Filtering', link: '/examples/filtering' },
          { text: 'Sampling', link: '/examples/sampling' },
          { text: 'Redaction', link: '/examples/redaction' },
          { text: 'Metrics', link: '/examples/metrics' },
          { text: 'Tracing', link: '/examples/tracing' },
          { text: 'Compression', link: '/examples/compression' },
          { text: 'Thread Pool', link: '/examples/thread-pool' },
          { text: 'Scheduler', link: '/examples/scheduler' },
          { text: 'Dynamic Path', link: '/examples/dynamic-path' },
          { text: 'Sink Write Modes', link: '/examples/write-modes' },
          { text: 'Production Config', link: '/examples/production-config' },
          { text: 'Diagnostics', link: '/examples/diagnostics' },
          { text: 'Customizations', link: '/examples/customizations' }
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
