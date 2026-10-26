---
title: Akari
description: A themeable Linux greeter built with Flutter and Rust. Design custom login experiences with rich animations, shaders, and expressive themes.
template: splash
editUrl: false
hero:
  title: A modern Linux greeter.<br /><span>Powered by Flutter & Rust.</span>
  tagline: Bring custom layouts, rich animations, and shaders to your login screen. Build with Flutter’s expressive graphics pipeline while Rust keeps PAM authentication isolated and secure.
  actions:
    - text: Quick start
      link: /Akari/getting-started/quick-start/
      icon: right-arrow
    - text: Theme development
      link: /Akari/guides/themes/
      variant: secondary
---

<div class="akari-section-intro">
  <p class="akari-eyebrow">CREATIVE FREEDOM</p>
  <h2 id="make-it-yours">Bring your visual identity to the login screen.</h2>
  <p>From quiet, minimal typography to rich shader canvases, your greeter deserves the same aesthetic care as the rest of your desktop.</p>
</div>

<div class="akari-features">
  <section>
    <span class="akari-feature-number" aria-hidden="true">01 / DESIGN</span>
    <h3>Flutter graphics & widget ecosystem</h3>
    <p>Compose your greeter with familiar widgets, custom Canvas painting, and rich motion tools. Typography, palettes, layouts, and animations belong entirely to your theme.</p>
    <a href="/Akari/guides/themes/">Explore theme development <span aria-hidden="true">↗</span></a>
  </section>
  <section>
    <span class="akari-feature-number" aria-hidden="true">02 / CREATE</span>
    <h3>Visual scene editing</h3>
    <p>Inspect layers and tune scene properties with the in-development Theme Studio. With hot reload during development, you can refine your layout and components live on the canvas.</p>
    <a href="/Akari/reference/cli/#commands-and-targets">Open Theme Studio <span aria-hidden="true">↗</span></a>
  </section>
  <section>
    <span class="akari-feature-number" aria-hidden="true">03 / DISPLAY</span>
    <h3>Multi-display & HiDPI adaptation</h3>
    <p>Themes adapt to each monitor's native resolution and display scale. Account selection, desktop sessions, and authentication state stay synchronized across all screens.</p>
    <a href="/Akari/guides/display-testing/">Explore multiple displays <span aria-hidden="true">↗</span></a>
  </section>
  <section>
    <span class="akari-feature-number" aria-hidden="true">04 / ARCHITECTURE</span>
    <h3>Presentation on frontend, security in Rust</h3>
    <p>Your Flutter theme compiles to a native Linux interface, while an isolated Rust backend manages greetd and PAM authentication over a private D-Bus boundary.</p>
    <a href="/Akari/architecture/overview/">See how Akari works <span aria-hidden="true">↗</span></a>
  </section>
</div>

## Start Here

Preview the included themes on your desktop, then design your own.

| Goal | Guide |
| --- | --- |
| Set up development toolchain | [Installation](getting-started/installation.md) |
| Run desktop previews & mock sessions | [Quick start](getting-started/quick-start.md) |
| Build your own login theme | [Theme development](guides/themes.md) |
| Author custom Flutter widgets | [Component guide](guides/components.md) |
| Look up SDK types and methods | [API reference](reference/api.md) |
| Explore repository architecture | [Code map](architecture/code-map.md) |
