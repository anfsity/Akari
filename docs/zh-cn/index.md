---
title: Akari
description: 基于 Flutter 与 Rust 构建的现代 Linux 登录界面（Greeter）。支持自定义布局、丰富动效与着色器视觉，兼具高度定制性与认证安全性。
template: splash
editUrl: false
hero:
  title: <span class="akari-title-lead">现代、流畅、</span><span class="akari-title-lead">高度可定制的</span><br /><span>Linux 登录界面。</span>
  tagline: 基于 Flutter 与 Rust 构建。将生动的着色器特效、自定义布局与流畅动画带入开机界面，兼顾视觉表现力与系统级认证安全性。
  actions:
    - text: 快速开始
      link: /Akari/zh-cn/getting-started/quick-start/
      icon: right-arrow
    - text: 主题开发
      link: /Akari/zh-cn/guides/themes/
      variant: secondary
---

<div class="akari-section-intro">
  <p class="akari-eyebrow">自由表达</p>
  <h2 id="make-it-yours">将视觉创意带入系统登录。</h2>
  <p>从极简排版到丰富的着色器画布，登录界面可以拥有与你的桌面环境一致的精致美学。</p>
</div>

<div class="akari-features">
  <section>
    <span class="akari-feature-number" aria-hidden="true">01 / 自由设计</span>
    <div class="akari-feature-art akari-art-widgets" aria-hidden="true"><span></span><span></span><span></span><span></span></div>
    <h3>Flutter 丰富的组件与图形生态</h3>
    <p>借助熟悉的 Widget、自定义 Canvas 绘制与动画工具构建登录界面，字体、调色板、布局与细节均由主题自主掌控。</p>
    <a href="/Akari/zh-cn/guides/themes/">开始制作主题 <span aria-hidden="true">↗</span></a>
  </section>
  <section>
    <span class="akari-feature-number" aria-hidden="true">02 / 实时调试</span>
    <div class="akari-feature-art akari-art-canvas" aria-hidden="true"><span></span><span></span><span></span><span></span></div>
    <h3>Theme Studio 可视化画布</h3>
    <p>通过开发中的 Theme Studio 调整图层层级与节点属性，支持实时热重载，更直观地试验场景布局与组件效果。</p>
    <a href="/Akari/zh-cn/reference/cli/#commands-and-targets">了解 Theme Studio 启动方式 <span aria-hidden="true">↗</span></a>
  </section>
  <section>
    <span class="akari-feature-number" aria-hidden="true">03 / 多屏协同</span>
    <div class="akari-feature-art akari-art-displays" aria-hidden="true"><span></span><span></span><span></span><span></span></div>
    <h3>多显示器与 HiDPI 自适应</h3>
    <p>自动适配各显示器的物理分辨率与缩放比例。账户选择、桌面会话与登录状态在所有屏幕间全局同步，平滑切换焦点。</p>
    <a href="/Akari/zh-cn/guides/display-testing/">多显示器测试指南 <span aria-hidden="true">↗</span></a>
  </section>
  <section>
    <span class="akari-feature-number" aria-hidden="true">04 / 权责清晰</span>
    <div class="akari-feature-art akari-art-security" aria-hidden="true"><span></span><span></span><span></span><span></span></div>
    <h3>前端专注表现，后端把控安全</h3>
    <p>Flutter 主题编译为原生 Linux 界面，独立的 Rust 后端通过 greetd 与 PAM 处理身份验证，使主题开发免受特权与认证细节干扰。</p>
    <a href="/Akari/zh-cn/architecture/overview/">了解系统架构 <span aria-hidden="true">↗</span></a>
  </section>
</div>

## 从这里开始

先在本地桌面运行预览，体验内置主题，再开始构建你的专属设计。

<div class="akari-guides">
  <div class="akari-guide-labels"><span>目标</span><span>文档导航</span></div>
  <ul>
    <li><a href="/Akari/zh-cn/getting-started/installation/"><span>准备开发环境与依赖</span><strong>环境配置</strong><span class="akari-guide-arrow" aria-hidden="true">↗</span></a></li>
    <li><a href="/Akari/zh-cn/getting-started/quick-start/"><span>桌面预览与模拟运行</span><strong>快速开始</strong><span class="akari-guide-arrow" aria-hidden="true">↗</span></a></li>
    <li><a href="/Akari/zh-cn/guides/themes/"><span>定制专属登录主题</span><strong>主题开发</strong><span class="akari-guide-arrow" aria-hidden="true">↗</span></a></li>
    <li><a href="/Akari/zh-cn/guides/components/"><span>编写自定义 Flutter 组件</span><strong>组件开发</strong><span class="akari-guide-arrow" aria-hidden="true">↗</span></a></li>
    <li><a href="/Akari/zh-cn/reference/api/"><span>查阅 SDK 类型与方法</span><strong>API 参考</strong><span class="akari-guide-arrow" aria-hidden="true">↗</span></a></li>
    <li><a href="/Akari/zh-cn/architecture/code-map/"><span>了解仓库结构与参与开发</span><strong>代码导航</strong><span class="akari-guide-arrow" aria-hidden="true">↗</span></a></li>
  </ul>
</div>
