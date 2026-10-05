import { defineMiddleware } from 'astro:middleware';

const showEditLinks = process.env.AKARI_DOCS_EDIT_LINKS !== 'false';

/** Localized index slugs omit `/index`, so edit links use the source file path. */
export const onRequest = defineMiddleware((context, next) => {
  const route = context.locals.starlightRoute;
  if (showEditLinks && route.entry.data.editUrl !== false) {
    const sourcePath = route.entry.filePath.replace(/^\.\.\//, '');
    route.editUrl = new URL(`https://github.com/anfsity/Akari/edit/main/docs/${sourcePath}`);
  }
  return next();
});
