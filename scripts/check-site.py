"""Checks the static website in the given directory against the rules the page must keep.

    python3 -I scripts/check-site.py site

Prints one line per problem and exits 1, or prints "<directory> OK" and exits 0.
"""

import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

LATEST_DOWNLOAD = "https://github.com/JonasDoebertin/ajour/releases/latest/download/Ajour.zip"
CSS_URL = re.compile(r"url\(\s*['\"]?([^'\")]+)['\"]?\s*\)")


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.references = []
        self.external_loads = []
        self.scripts = []
        self.json_ld = []
        self.images = []
        self.lists_without_role = []
        self.h1_count = 0
        self.links = []
        self.visible_text = []
        self._script_type = None
        self._script_text = []
        self._skip_depth = 0
        self._open_link = None

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag in ("script", "style"):
            self._skip_depth += 1
        if tag == "script":
            self._script_type = attributes.get("type", "")
            self._script_text = []
            self.scripts.append((self._script_type, attributes.get("src")))
            if "src" in attributes:
                self.references.append(("script src", attributes["src"]))
        if tag == "h1":
            self.h1_count += 1
        if tag == "img":
            self.images.append(attributes)
        if tag in ("ol", "ul") and attributes.get("role") != "list":
            self.lists_without_role.append(attributes.get("class", tag))
        if tag == "a":
            self._open_link = {"href": attributes.get("href", ""), "text": []}
        for name in ("src", "href"):
            value = attributes.get(name)
            if value is None or (tag == "script" and name == "src"):
                continue
            if tag == "a":
                if value.startswith("/"):
                    self.references.append((f"<a {name}>", value))
                continue
            if tag == "link" and attributes.get("rel") == "canonical":
                continue
            self.references.append((f"<{tag} {name}>", value))
        if "srcset" in attributes:
            for candidate in attributes["srcset"].split(","):
                self.references.append((f"<{tag} srcset>", candidate.strip().split(" ")[0]))

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self._skip_depth -= 1
        if tag == "script":
            if self._script_type == "application/ld+json":
                self.json_ld.append("".join(self._script_text))
            self._script_type = None
        if tag == "a" and self._open_link is not None:
            self.links.append({"href": self._open_link["href"], "text": " ".join("".join(self._open_link["text"]).split())})
            self._open_link = None

    def handle_data(self, data):
        if self._script_type is not None:
            self._script_text.append(data)
        if self._skip_depth == 0:
            self.visible_text.append(data)
        if self._open_link is not None:
            self._open_link["text"].append(data)


def is_external(url):
    return re.match(r"^[a-z][a-z0-9+.-]*:|^//", url, re.IGNORECASE) is not None


def local_problem(site, base, url):
    path = url.split("#")[0].split("?")[0]
    if not path:
        return None
    target = (base / path).resolve()
    if not target.is_relative_to(site):
        return "points outside the site directory, which is all that gets deployed"
    if not target.is_file():
        return "does not exist"
    return None


def check(site):
    problems = []
    index = site / "index.html"
    if not index.is_file():
        return ["index.html is missing"]

    page = Page()
    page.feed(index.read_text(encoding="utf-8"))

    for where, url in page.references:
        if url.startswith("/"):
            problems.append(f"{where} {url} is root-relative; use a relative URL so the page works under any path")
        elif is_external(url):
            problems.append(f"{where} {url} loads from another server")
        elif problem := local_problem(site, site, url):
            problems.append(f"{where} {url} {problem}")

    for stylesheet in site.rglob("*.css"):
        text = stylesheet.read_text(encoding="utf-8")
        if "@import" in text:
            problems.append(f"{stylesheet.name} uses @import")
        for url in CSS_URL.findall(text):
            if url.startswith("data:"):
                continue
            if url.startswith("/"):
                problems.append(f"{stylesheet.name} url({url}) is root-relative")
            elif is_external(url):
                problems.append(f"{stylesheet.name} url({url}) loads from another server")
            elif problem := local_problem(site, stylesheet.parent, url):
                problems.append(f"{stylesheet.name} url({url}) {problem}")

    for script_type, source in page.scripts:
        if script_type == "application/ld+json" and source is None:
            continue
        if script_type == "module" and source is not None:
            continue
        problems.append(f"<script type=\"{script_type}\"> is not allowed; only module scripts from site/ may run")

    visible = " ".join(" ".join(page.visible_text).split())
    for block in page.json_ld:
        if "Review" in block or "aggregateRating" in block:
            problems.append("JSON-LD contains review or rating markup")
        try:
            data = json.loads(block)
        except json.JSONDecodeError as error:
            problems.append(f"JSON-LD does not parse: {error}")
            continue
        if data.get("@type") == "FAQPage":
            for question in data.get("mainEntity", []):
                name = question.get("name", "")
                answer = question.get("acceptedAnswer", {}).get("text", "")
                if name not in visible:
                    problems.append(f"FAQ question not on the page: {name}")
                if answer not in visible:
                    problems.append(f"FAQ answer not on the page: {answer}")

    for name in page.lists_without_role:
        problems.append(f"list {name} needs role=\"list\"; without list markers, Safari drops its list semantics")

    if page.h1_count != 1:
        problems.append(f"the page has {page.h1_count} <h1> elements instead of one")

    for image in page.images:
        name = image.get("src", "?")
        if "alt" not in image:
            problems.append(f"<img {name}> has no alt attribute")
        if "width" not in image or "height" not in image:
            problems.append(f"<img {name}> has no width and height")

    downloads = [link for link in page.links if "Download Ajour" in link["text"]]
    if len(downloads) < 2:
        problems.append(f"the page has {len(downloads)} download links instead of at least two")
    for link in downloads:
        if link["href"] != LATEST_DOWNLOAD:
            problems.append(f"download link points to {link['href']}")

    return problems


def main():
    if len(sys.argv) != 2:
        print("usage: python3 -I scripts/check-site.py <site directory>")
        return 2
    site = Path(sys.argv[1]).resolve()
    problems = check(site)
    for problem in problems:
        print(problem)
    if problems:
        return 1
    print(f"{sys.argv[1]} OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
