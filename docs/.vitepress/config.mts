import { defineConfig } from "vitepress";
import llmstxt from "vitepress-plugin-llms";

// Site configuration
export const SITE_URL = "https://muhammad-fiaz.github.io/logly.zig";
export const SITE_NAME = "Logly.zig";
export const SITE_DESCRIPTION = "High-performance structured logging library for Zig with async I/O, file rotation, JSON output, ANSI colors, and enterprise features like redaction, metrics, and distributed tracing.";

// Google Analytics and Google Tag Manager IDs
export const GA_ID = "G-6BVYCRK57P";
export const GTM_ID = "GTM-P4M9T8ZR";

// SEO Keywords
export const KEYWORDS = "zig, logging, logger, structured logging, async logging, json logging, file rotation, log rotation, thread pool, metrics, tracing, redaction, filtering, sampling, compression, network logging, zig library, production logging, enterprise logging";

export default defineConfig({
  lang: "en-US",
  title: SITE_NAME,
  description: SITE_DESCRIPTION,
  base: "/logly.zig/",
  lastUpdated: true,
  cleanUrls: true,
  
  sitemap: {
    hostname: SITE_URL,
  },

  vite: {
    plugins: [llmstxt()],
  },

  head: [
    // Primary Meta Tags
    ["meta", { name: "title", content: SITE_NAME }],
    ["meta", { name: "description", content: SITE_DESCRIPTION }],
    ["meta", { name: "keywords", content: KEYWORDS }],
    ["meta", { name: "author", content: "Muhammad Fiaz" }],
    ["meta", { name: "robots", content: "index, follow" }],
    ["meta", { name: "language", content: "English" }],
    ["meta", { name: "revisit-after", content: "7 days" }],
    ["meta", { name: "generator", content: "VitePress" }],
    
    // Open Graph / Facebook
    ["meta", { property: "og:type", content: "website" }],
    ["meta", { property: "og:url", content: SITE_URL }],
    ["meta", { property: "og:title", content: SITE_NAME }],
    ["meta", { property: "og:description", content: SITE_DESCRIPTION }],
    ["meta", { property: "og:image", content: `${SITE_URL}/cover.png` }],
    ["meta", { property: "og:image:width", content: "1200" }],
    ["meta", { property: "og:image:height", content: "630" }],
    ["meta", { property: "og:image:alt", content: "Logly.zig - High Performance Zig Logging Library" }],
    ["meta", { property: "og:site_name", content: SITE_NAME }],
    ["meta", { property: "og:locale", content: "en_US" }],

    // Twitter Card
    ["meta", { name: "twitter:card", content: "summary_large_image" }],
    ["meta", { name: "twitter:url", content: SITE_URL }],
    ["meta", { name: "twitter:title", content: SITE_NAME }],
    ["meta", { name: "twitter:description", content: SITE_DESCRIPTION }],
    ["meta", { name: "twitter:image", content: `${SITE_URL}/cover.png` }],
    ["meta", { name: "twitter:creator", content: "@muhammadfiaborz" }],

    // Canonical URL
    ["link", { rel: "canonical", href: SITE_URL }],

    // JSON-LD Schema for Software Application
    [
      "script",
      { type: "application/ld+json" },
      JSON.stringify({
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": "Logly.zig",
        "applicationCategory": "DeveloperApplication",
        "operatingSystem": "Cross-platform",
        "programmingLanguage": "Zig",
        "offers": {
          "@type": "Offer",
          "price": "0",
          "priceCurrency": "USD"
        },
        "author": {
          "@type": "Person",
          "name": "Muhammad Fiaz",
          "url": "https://github.com/muhammad-fiaz"
        },
        "description": SITE_DESCRIPTION,
        "url": SITE_URL,
        "downloadUrl": "https://github.com/muhammad-fiaz/logly.zig",
        "softwareVersion": "0.0.9",
        "license": "https://opensource.org/licenses/MIT"
      })
    ],

    // JSON-LD Schema for Documentation
    [
      "script",
      { type: "application/ld+json" },
      JSON.stringify({
        "@context": "https://schema.org",
        "@type": "TechArticle",
        "headline": "Logly.zig Documentation",
        "description": SITE_DESCRIPTION,
        "author": {
          "@type": "Person",
          "name": "Muhammad Fiaz"
        },
        "publisher": {
          "@type": "Person",
          "name": "Muhammad Fiaz"
        },
        "mainEntityOfPage": {
          "@type": "WebPage",
          "@id": SITE_URL
        },
        "image": `${SITE_URL}/cover.png`
      })
    ],

    // Favicons
    ["link", { rel: "icon", href: "/logly.zig/favicon.ico" }],
    ["link", { rel: "icon", type: "image/png", sizes: "16x16", href: "/logly.zig/favicon-16x16.png" }],
    ["link", { rel: "icon", type: "image/png", sizes: "32x32", href: "/logly.zig/favicon-32x32.png" }],
    ["link", { rel: "apple-touch-icon", sizes: "180x180", href: "/logly.zig/apple-touch-icon.png" }],
    ["link", { rel: "icon", type: "image/png", sizes: "192x192", href: "/logly.zig/android-chrome-192x192.png" }],
    ["link", { rel: "icon", type: "image/png", sizes: "512x512", href: "/logly.zig/android-chrome-512x512.png" }],
    ["link", { rel: "manifest", href: "/logly.zig/site.webmanifest" }],

    // Theme color
    ["meta", { name: "theme-color", content: "#f7a41d" }],
    ["meta", { name: "msapplication-TileColor", content: "#f7a41d" }],

    // Google Analytics (gtag.js)
    [
      "script",
      { async: "", src: `https://www.googletagmanager.com/gtag/js?id=${GA_ID}` },
    ],
    [
      "script",
      {},
      `window.dataLayer = window.dataLayer || [];
function gtag(){dataLayer.push(arguments);}
gtag('js', new Date());
gtag('config', '${GA_ID}');`,
    ],

    // Google Tag Manager
    ...(GTM_ID
      ? ([
          [
            "script",
            {},
            `(function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start': new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0], j=d.createElement(s), dl=l!='dataLayer'?'&l='+l:''; j.async=true; j.src='https://www.googletagmanager.com/gtm.js?id='+i+dl; f.parentNode.insertBefore(j,f);})(window,document,'script','dataLayer','${GTM_ID}');`,
          ],
          [
            "noscript",
            {},
            `<iframe src="https://www.googletagmanager.com/ns.html?id=${GTM_ID}" height="0" width="0" style="display:none;visibility:hidden"></iframe>`,
          ],
        ] as [string, Record<string, string>, string][])
      : []),
  ],

  ignoreDeadLinks: [/.*\.zig$/],

  transformPageData(pageData) {
    // Dynamic OG image generation based on page title
    const pageTitle = pageData.title || SITE_NAME;
    const pageDescription = pageData.description || SITE_DESCRIPTION;
    const canonicalUrl = `${SITE_URL}${pageData.relativePath.replace(/\.md$/, '.html').replace(/index\.html$/, '')}`;

    pageData.frontmatter.head ??= [];
    pageData.frontmatter.head.push(
      ["link", { rel: "canonical", href: canonicalUrl }],
      ["meta", { property: "og:title", content: `${pageTitle} | ${SITE_NAME}` }],
      ["meta", { property: "og:url", content: canonicalUrl }]
    );

    if (pageData.frontmatter.description) {
      pageData.frontmatter.head.push(
        ["meta", { property: "og:description", content: pageData.frontmatter.description }],
        ["meta", { name: "description", content: pageData.frontmatter.description }]
      );
    }
  },

  themeConfig: {
    logo: "/logo.png",
    siteTitle: "Logly.zig",

    nav: [
      { text: "Home", link: "/" },
      { text: "Guide", link: "/guide/getting-started" },
      { text: "API", link: "/api/logger" },
      { text: "Examples", link: "/examples/basic" },
      { text: "Comparison", link: "/guide/comparison" },
      {
        text: "Support",
        items: [
          { text: "💖 Sponsor", link: "https://github.com/sponsors/muhammad-fiaz" },
          { text: "☕ Donate", link: "https://pay.muhammadfiaz.com" },
        ],
      },
      { text: "GitHub", link: "https://github.com/muhammad-fiaz/logly.zig" },
    ],

    sidebar: [
      {
        text: "Introduction",
        items: [
          { text: "What is Logly?", link: "/guide/introduction" },
          { text: "Comparison", link: "/guide/comparison" },
          { text: "Installation", link: "/guide/installation" },
          { text: "Getting Started", link: "/guide/getting-started" },
          { text: "Quick Start", link: "/guide/quick-start" },
        ],
      },
      {
        text: "Core Concepts",
        items: [
          { text: "Log Levels", link: "/guide/log-levels" },
          { text: "Configuration", link: "/guide/configuration" },
          { text: "Colors & Styling", link: "/guide/colors" },
          { text: "Sinks", link: "/guide/sinks" },
          { text: "Formatting", link: "/guide/formatting" },
          { text: "Custom Levels", link: "/guide/custom-levels" },
        ],
      },
      {
        text: "Core Features",
        items: [
          { text: "File Rotation", link: "/guide/rotation" },
          { text: "JSON Logging", link: "/guide/json" },
          { text: "Context Binding", link: "/guide/context" },
          { text: "Callbacks", link: "/guide/callbacks" },
          { text: "Source Location", link: "/guide/source-location" },
          { text: "Stack Traces", link: "/guide/stack-traces" },
        ],
      },
      {
        text: "Advanced Features",
        items: [
          { text: "Async Logging", link: "/guide/async" },
          { text: "Compression", link: "/guide/compression" },
          { text: "Thread Pool", link: "/guide/thread-pool" },
          { text: "Scheduler", link: "/guide/scheduler" },
          { text: "Rules System", link: "/guide/rules" },
          { text: "Arena Allocation", link: "/guide/arena-allocation" },
          { text: "Network Logging", link: "/guide/network-logging" },
        ],
      },
      {
        text: "System & Operations",
        items: [
          { text: "System Diagnostics", link: "/guide/diagnostics" },
          { text: "Update Checker", link: "/guide/update-checker" },
        ],
      },
      {
        text: "Enterprise Features",
        items: [
          { text: "Filtering", link: "/guide/filtering" },
          { text: "Sampling", link: "/guide/sampling" },
          { text: "Redaction", link: "/guide/redaction" },
          { text: "Metrics", link: "/guide/metrics" },
          { text: "Distributed Tracing", link: "/guide/tracing" },
          { text: "Customizations", link: "/guide/customizations" },
        ],
      },
      {
        text: "API Reference",
        items: [
          { text: "Logger", link: "/api/logger" },
          { text: "Config", link: "/api/config" },
          { text: "Level", link: "/api/level" },
          { text: "Sink", link: "/api/sink" },
          { text: "Formatter", link: "/api/formatter" },
          { text: "Rotation", link: "/api/rotation" },
          { text: "Rules", link: "/api/rules" },
          { text: "Filter", link: "/api/filter" },
          { text: "Sampler", link: "/api/sampler" },
          { text: "Redactor", link: "/api/redactor" },
          { text: "Metrics", link: "/api/metrics" },
          { text: "Network", link: "/api/network" },
          { text: "Update Checker", link: "/api/update-checker" },
          { text: "Record", link: "/api/record" },
          { text: "Async Queue", link: "/api/async" },
          { text: "Compression", link: "/api/compression" },
          { text: "Thread Pool", link: "/api/thread-pool" },
          { text: "Scheduler", link: "/api/scheduler" },
          { text: "Diagnostics", link: "/api/diagnostics" },
          { text: "Constants", link: "/api/constants" },
          { text: "Customizations", link: "/api/customizations" },
          { text: "Utils", link: "/api/utils" },
          { text: "Date Formatting", link: "/api/date-formatting" },
        ],
      },
      {
        text: "Code Examples",
        items: [
          { text: "Basic Usage", link: "/examples/basic" },
          { text: "File Logging", link: "/examples/file-logging" },
          { text: "Rotation", link: "/examples/rotation" },
          { text: "JSON Logging", link: "/examples/json" },
          { text: "JSON Extended", link: "/examples/json-extended" },
          { text: "Rules System", link: "/examples/rules" },
          { text: "Custom Colors", link: "/examples/custom-colors" },
          { text: "Custom Theme", link: "/examples/custom-theme" },
          { text: "Color Control", link: "/examples/color-control" },
          { text: "Context", link: "/examples/context" },
          { text: "Callbacks", link: "/examples/callbacks" },
          { text: "Async Logging", link: "/examples/async-logging" },
          { text: "Network Logging", link: "/examples/network-logging" },
          { text: "Advanced Config", link: "/examples/advanced-config" },
          { text: "Module Levels", link: "/examples/module-levels" },
          { text: "Custom Levels Full", link: "/examples/custom-levels-full" },
          { text: "Sink Formats", link: "/examples/sink-formats" },
          { text: "Formatted Logging", link: "/examples/formatted-logging" },
          { text: "Time Formatting", link: "/examples/time" },
          { text: "Filtering", link: "/examples/filtering" },
          { text: "Sampling", link: "/examples/sampling" },
          { text: "Redaction", link: "/examples/redaction" },
          { text: "Metrics", link: "/examples/metrics" },
          { text: "Tracing", link: "/examples/tracing" },
          { text: "Compression", link: "/examples/compression" },
          { text: "Thread Pool", link: "/examples/thread-pool" },
          { text: "Scheduler", link: "/examples/scheduler" },
          { text: "Dynamic Path", link: "/examples/dynamic-path" },
          { text: "Sink Write Modes", link: "/examples/write-modes" },
          { text: "Production Config", link: "/examples/production-config" },
          { text: "Diagnostics", link: "/examples/diagnostics" },
          { text: "Customizations", link: "/examples/customizations" },
        ],
      },
    ],

    socialLinks: [
      { icon: "github", link: "https://github.com/muhammad-fiaz/logly.zig" },
    ],

    footer: {
      message: "Released under the MIT License.",
      copyright: "Copyright © 2025 Muhammad Fiaz",
    },

    search: {
      provider: "local",
    },

    editLink: {
      pattern: "https://github.com/muhammad-fiaz/logly.zig/edit/main/docs/:path",
      text: "Edit this page on GitHub",
    },

    lastUpdated: {
      text: "Last updated",
      formatOptions: {
        dateStyle: "medium",
        timeStyle: "short",
      },
    },
  },
});
