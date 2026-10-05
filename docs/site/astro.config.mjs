import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { unified } from '@astrojs/markdown-remark';
import { remarkDocs } from './src/remark-docs.mjs';

export default defineConfig({
  site: 'https://anfsity.github.io',
  base: '/Akari',
  trailingSlash: 'always',
  markdown: { processor: unified({ remarkPlugins: [remarkDocs] }) },
  integrations: [
    starlight({
      title: 'Akari',
      description: 'Build compile-time Flutter themes for a Linux greeter.',
      locales: {
        root: { label: 'English', lang: 'en' },
        'zh-cn': { label: '简体中文', lang: 'zh-CN' },
      },
      favicon: '/favicon.svg',
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/anfsity/Akari' }],
      routeMiddleware: './src/route-data.ts',
      expressiveCode: false,
      customCss: ['./src/styles/custom.css'],
      components: { Head: './src/components/Head.astro' },
      sidebar: [
        { label: 'Start here', translations: { 'zh-CN': '开始使用' }, items: [
          { slug: 'getting-started/installation', translations: { 'zh-CN': '环境配置' } },
          { slug: 'getting-started/quick-start', translations: { 'zh-CN': '快速开始' } },
        ] },
        { label: 'Theme development', translations: { 'zh-CN': '主题开发' }, items: [
          { slug: 'guides/themes', translations: { 'zh-CN': '开发主题' } },
          { slug: 'guides/components', translations: { 'zh-CN': '开发主题组件' } },
          { slug: 'guides/testing', translations: { 'zh-CN': '开发与测试' } },
          { slug: 'guides/display-testing', translations: { 'zh-CN': '显示器与缩放测试' } },
        ] },
        { label: 'Technical reference', translations: { 'zh-CN': '技术参考' }, items: [
          { slug: 'reference/theme-package', translations: { 'zh-CN': '主题包约定' } },
          { slug: 'reference/scene-format', translations: { 'zh-CN': '场景格式' } },
          { slug: 'reference/cli', translations: { 'zh-CN': 'CLI 与开发工具' } },
          { slug: 'reference/dbus', translations: { 'zh-CN': 'D-Bus 接口约定' } },
          { slug: 'reference/api', translations: { 'zh-CN': 'API 参考' } },
        ] },
        { label: 'Contributing', translations: { 'zh-CN': '参与贡献' }, items: [
          { slug: 'architecture/overview', translations: { 'zh-CN': '系统概览' } },
          { slug: 'architecture/code-map', translations: { 'zh-CN': '代码导航' } },
          { slug: 'architecture/frontend', translations: { 'zh-CN': '前端架构' } },
          { slug: 'architecture/backend', translations: { 'zh-CN': '后端代码指南' } },
          { slug: 'guides/greetd-testing', translations: { 'zh-CN': '独立 greetd 测试' } },
          { slug: 'guides/documentation', translations: { 'zh-CN': '维护文档' } },
        ] },
      ],
    }),
  ],
});
