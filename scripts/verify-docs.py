#!/usr/bin/env python3
"""Validate the published handbook's local links against the complete build."""

import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit


class PageLinks(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.links = []
        self.ids = set()
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if tag == "a" and "href" in attrs:
            self.links.append(attrs["href"])
        if tag in {"script", "img", "link"} and (attrs.get("src") or attrs.get("href")):
            self.links.append(attrs.get("src") or attrs["href"])


def validate_site(root):
    pages = {file: PageLinks(file.read_text()) for file in root.rglob("*.html")}
    errors = []
    handbook = [file for file in pages if not file.relative_to(root).as_posix().startswith("api/")]
    for file in handbook:
        relative = file.relative_to(root).as_posix()
        page_url = "/Akari/" + (relative[:-10] if relative.endswith("index.html") else relative)
        for link in pages[file].links:
            url = urlsplit(urljoin(page_url, link))
            if url.scheme or url.netloc:
                continue
            if not url.path.startswith("/Akari/"):
                errors.append(f"{relative}: link escapes /Akari/: {link}")
                continue
            target = root / unquote(url.path.removeprefix("/Akari/"))
            if target.is_dir():
                target /= "index.html"
            if not target.is_file():
                errors.append(f"{relative}: missing target: {link}")
                continue
            if url.fragment and target in pages and unquote(url.fragment) not in pages[target].ids:
                errors.append(f"{relative}: missing fragment: {link}")
    for package in ("theme_sdk", "scene", "scene_schema", "greeter_components"):
        entrypoint = root / "api" / "dart" / package / "index.html"
        if not entrypoint.is_file():
            errors.append(f"missing API entrypoint: {package}")
        elif "/Akari/reference/api/" not in pages[entrypoint].links:
            errors.append(f"missing handbook navigation in API reference: {package}")
    for directory in ("internal", "proposals"):
        if (root / directory).exists():
            errors.append(f"repository-only documents were published: {directory}")
    if not handbook:
        errors.append("no handbook pages were generated")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Verified {len(handbook)} handbook pages and four API entrypoints.")


if __name__ == "__main__":
    validate_site(Path(sys.argv[1]).resolve())
