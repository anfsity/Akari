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
      ],
      generateId: ({ entry }) => entry.replace(/\.md$/, ''),
    }),
    schema: docsSchema(),
  }),
};
