---
title: Akari
description: 用 Flutter 打造的现代 Linux 登录界面。自由设计背景、布局和动画，让每次开机都有自己的风格。
template: splash
editUrl: false
hero:
  title: 你的 Linux，<br /><span>从登录就与众不同。</span>
  tagline: Akari 是用 Flutter 打造的现代 Linux 登录界面。背景、布局、组件和动画都可以按你的喜好设计，让每次开机都有自己的风格。
  actions:
    - text: 试试 Akari
      link: /Akari/zh-cn/getting-started/quick-start/
      icon: right-arrow
    - text: 做一个自己的主题
      link: /Akari/zh-cn/guides/themes/
      variant: secondary
---

<div class="akari-section-intro">
  <p class="akari-eyebrow">好看的桌面，从登录开始</p>
  <h2 id="make-it-yours">从一张壁纸，到一整套风格。</h2>
  <p>喜欢清爽简洁，还是想让动画和色彩多一点？登录界面也可以和你的桌面一样，按自己的喜好来。</p>
</div>

<div class="akari-features">
  <section>
    <span class="akari-feature-number" aria-hidden="true">01 / 自由设计</span>
    <h3>会写 Flutter，就能做主题。</h3>
    <p>用熟悉的 widget、自定义绘制和动画工具，做出你想要的登录界面。字体、配色、布局和细节，都由你来定。</p>
    <a href="/Akari/zh-cn/guides/themes/">开始制作主题 <span aria-hidden="true">↗</span></a>
  </section>
  <section>
    <span class="akari-feature-number" aria-hidden="true">02 / 边改边看</span>
    <h3>想法有了，就在画布上试试。</h3>
    <p>在 Theme Studio 里拖动图层、调整属性，直接看效果。开发时还可以用热重载，保存修改后就能继续预览。</p>
    <a href="/Akari/zh-cn/reference/cli/#commands-and-targets">打开 Theme Studio <span aria-hidden="true">↗</span></a>
  </section>
  <section>
    <span class="akari-feature-number" aria-hidden="true">03 / 多屏支持</span>
    <h3>换一块屏幕，也一样顺手。</h3>
    <p>主题会适应各块屏幕的分辨率和缩放。账户、桌面会话和登录状态保持同步，从这块屏幕切到那块，也能接着操作。</p>
    <a href="/Akari/zh-cn/guides/display-testing/">看看多屏怎么用 <span aria-hidden="true">↗</span></a>
  </section>
  <section>
    <span class="akari-feature-number" aria-hidden="true">04 / 专心创作</span>
    <h3>你来设计界面，Akari 处理登录。</h3>
    <p>Flutter 主题构建成原生 Linux 应用，Rust 后端通过 greetd 和 PAM 处理身份验证。写主题时，可以把精力放在外观和交互上。</p>
    <a href="/Akari/zh-cn/architecture/overview/">了解 Akari 的实现 <span aria-hidden="true">↗</span></a>
  </section>
</div>

## 先在桌面上试试

打开预览，看看内置主题，再动手做一个自己的版本。

| 想做什么 | 从这里开始 |
| --- | --- |
| 安装需要的开发工具 | [环境配置](getting-started/installation.md) |
| 在桌面上看看 Akari | [快速开始](getting-started/quick-start.md) |
| 制作自己的登录主题 | [主题开发](guides/themes.md) |
| 写一个 Flutter 组件 | [组件开发](guides/components.md) |
| 查 SDK 类型和方法 | [API 参考](reference/api.md) |
| 参与项目开发 | [代码导航](architecture/code-map.md) |
