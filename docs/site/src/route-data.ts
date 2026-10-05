import { defineMiddleware } from 'astro:middleware';

const showEditLinks = process.env.MOZAIS_DOCS_EDIT_LINKS !== 'false';

/** The content lives outside Astro's conventional src/content/docs directory. */
export const onRequest = defineMiddleware((context, next) => {
  const route = context.locals.starlightRoute;
  if (showEditLinks && route.entry.data.editUrl !== false) {
    route.editUrl = new URL(`https://github.com/anfsity/Mozais/edit/main/docs/${route.entry.id}.md`);
  }
  return next();
});
