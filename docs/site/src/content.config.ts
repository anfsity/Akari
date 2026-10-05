import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { docsSchema, i18nSchema } from '@astrojs/starlight/schema';
import { i18nLoader } from '@astrojs/starlight/loaders';

export const collections = {
  i18n: defineCollection({ loader: i18nLoader(), schema: i18nSchema() }),
  docs: defineCollection({
    loader: glob({
      base: new URL('../../', import.meta.url),
      pattern: [
        'index.md',
        '404.md',
        'getting-started/**/*.md',
        'guides/**/*.md',
        'reference/**/*.md',
        'architecture/**/*.md',
        'zh-cn/index.md',
        'zh-cn/404.md',
        'zh-cn/getting-started/**/*.md',
        'zh-cn/guides/**/*.md',
        'zh-cn/reference/**/*.md',
        'zh-cn/architecture/**/*.md',
      ],
      generateId: ({ entry }) => {
        const id = entry.replace(/\.md$/, '');
        return id === 'index' ? id : id.replace(/\/index$/, '');
      },
    }),
    schema: docsSchema(),
  }),
};
