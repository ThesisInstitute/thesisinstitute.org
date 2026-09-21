"""Check featured forecasts, including withdrawn pages that still return HTTP 200."""

import sys
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


class Page(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.featured = []
        self.links = []
        self.text = []
        self.headings = 0
        self.hidden = 0
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ("script", "style"):
            self.hidden += 1
        if tag in ("h1", "h2"):
            self.headings += 1
        if tag == "a":
            href = attrs.get("href", "")
            self.links.append(href)
            if "fcard" in attrs.get("class", "").split():
                self.featured.append(href)

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.hidden = max(0, self.hidden - 1)

    def handle_data(self, data):
        if not self.hidden:
            self.text.append(data)


def fetch(url):
    for attempt in range(3):
        try:
            request = Request(url, headers={"User-Agent": "Thesis-homepage-link-check"})
            with urlopen(request, timeout=30) as response:
                if response.status != 200:
                    raise ValueError(f"HTTP {response.status}: {url}")
                return response.geturl(), response.read().decode("utf-8")
        except (OSError, ValueError):
            if attempt == 2:
                raise
            time.sleep(2)


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "index.html"
    html = fetch(source)[1] if source.startswith("https://") else Path(source).read_text()
    links = Page(html).featured
    if not links:
        raise ValueError("Homepage has no featured forecast links to check")
    for url in links:
        parsed = urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc != "app.thesisinstitute.org":
            raise ValueError(f"Unexpected forecast destination: {url}")
        final_url, body = fetch(url)
        if final_url.rstrip("/") != url.rstrip("/"):
            raise ValueError(f"Use the canonical forecast URL: {url} -> {final_url}")
        page = Page(body)
        visible = " ".join(" ".join(page.text).split()).casefold()
        if "no forecast available" in visible or "this page could not be found" in visible:
            raise ValueError(f"Withdrawn or missing forecast: {url}")
        has_run_record = any(
            link.startswith("https://github.com/ThesisInstitute/thesis/")
            and "/records/thesis-analyst/" in link
            for link in page.links
        )
        if not page.headings or "run record" not in visible or not has_run_record:
            raise ValueError(f"Forecast is missing its published run record: {url}")
        print(f"PASS published forecast: {url}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(f"FAIL {error}")
