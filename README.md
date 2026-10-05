# Documentation publication

This branch triggers the [Akari documentation site](https://anfsity.github.io/Akari/).
It contains the publication workflow rather than generated website files.

Pushing `gh-pages`, or manually running **Publish documentation** in GitHub
Actions, calls `.github/workflows/docs.yml` from `main` with `source_ref: main`.
That workflow checks out the latest main source, generates the Dart API reference,
builds and verifies the handbook, and deploys its Pages artifact.

Edit documentation on `main`. Generated HTML, API pages, and search assets are
not committed to this branch. The initial static snapshot remains in the previous
commit for recovery.

See the [documentation maintenance guide](https://github.com/anfsity/Akari/blob/main/docs/guides/documentation.md)
for local preview and build commands.
