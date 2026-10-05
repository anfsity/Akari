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
      favicon: '/favicon.svg',
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/anfsity/Akari' }],
      routeMiddleware: './src/route-data.ts',
      expressiveCode: false,
      customCss: ['./src/styles/custom.css'],
      components: { Head: './src/components/Head.astro' },
      sidebar: [
        { label: 'Start here', items: [
          { slug: 'getting-started/installation' },
          { slug: 'getting-started/quick-start' },
        ] },
        { label: 'Theme development', items: [
          { slug: 'guides/themes' },
          { slug: 'guides/components' },
          { slug: 'guides/testing' },
          { slug: 'guides/display-testing' },
        ] },
        { label: 'Technical reference', items: [
          { slug: 'reference/theme-package' },
          { slug: 'reference/scene-format' },
          { slug: 'reference/cli' },
          { slug: 'reference/dbus' },
          { slug: 'reference/api' },
        ] },
        { label: 'Contributing', items: [
          { slug: 'architecture/overview' },
          { slug: 'architecture/code-map' },
          { slug: 'architecture/frontend' },
          { slug: 'architecture/backend' },
          { slug: 'guides/greetd-testing' },
          { slug: 'guides/documentation' },
        ] },
      ],
    }),
  ],
});
