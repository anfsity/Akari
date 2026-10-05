import path from 'node:path';
import { fileURLToPath } from 'node:url';

const docsRoot = fileURLToPath(new URL('../../', import.meta.url));

/** Keep Markdown links useful in GitHub while publishing directory URLs. */
export function remarkDocs() {
  return (tree, file) => {
    function updateNode(node) {
      if (node.type === 'link' && !/^(?:[a-z]+:|\/|#)/i.test(node.url)) {
        const [target, fragment] = node.url.split('#');
        if (target.endsWith('.md')) {
          const relative = path.relative(docsRoot, path.resolve(path.dirname(file.path), target));
          const route = relative.replace(/\.md$/, '').replace(/^index$/, '');
          node.url = `/Akari/${route}${route ? '/' : ''}${fragment ? `#${fragment}` : ''}`;
        }
      }
      if (node.type === 'code' && node.lang === 'mermaid') {
        const source = node.value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
        node.type = 'html';
        node.value = `<pre class="mermaid">${source}</pre>`;
        delete node.lang;
        delete node.meta;
      }
      for (const child of node.children ?? []) updateNode(child);
    }
    updateNode(tree);
  };
}
