import { mkdir, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { chromium } from "playwright";

const INPUT = await readInput();
const SETTINGS = buildSettings(INPUT);

let browser;
let context;

try {
  emitProgress(`Browser crawling ${new URL(INPUT.url).host}`);

  browser = await chromium.launch({
    headless: true,
    proxy: INPUT.proxy || undefined,
  });

  context = await browser.newContext({
    serviceWorkers: "block",
    userAgent: INPUT.user_agent,
  });

  await context.route("**/*", (route) => {
    const resourceType = route.request().resourceType();

    if (["image", "media", "font"].includes(resourceType)) {
      return route.abort();
    }

    return route.continue();
  });

  const result = await crawl(context, INPUT.url, SETTINGS);

  await mkdir(dirname(INPUT.output_path), { recursive: true });
  await writeFile(INPUT.output_path, JSON.stringify(result), "utf8");
  emit({ type: "result", output_path: INPUT.output_path });
} catch (error) {
  emit({
    type: "error",
    error_class: "transient",
    message: error instanceof Error ? error.message : "Node website crawler failed",
  });
  process.exitCode = 1;
} finally {
  await context?.close().catch(() => {});
  await browser?.close().catch(() => {});
}

async function crawl(context, seedUrl, settings) {
  const queue = [seedUrl];
  const visited = new Set();
  const pages = [];
  let crawledPages = 0;

  while (queue.length > 0 && canCrawlMorePages(settings, crawledPages)) {
    const currentUrl = queue.shift();
    const normalized = normalizeUrl(currentUrl);

    if (visited.has(normalized)) {
      continue;
    }

    visited.add(normalized);
    if (pages.length > 0 && settings.crawlDelayMs > 0) {
      await wait(settings.crawlDelayMs);
    }

    const page = await context.newPage();

    try {
      const snapshot = await capturePage(page, currentUrl, settings);
      if (!snapshot) {
        continue;
      }
      crawledPages += 1;

      if (canCrawlMorePages(settings, crawledPages)) {
        for (const link of snapshot.links) {
          const normalizedLink = normalizeUrl(link);
          if (!visited.has(normalizedLink)) {
            queue.push(link);
          }
        }
      }

      pages.push({ url: snapshot.url, html: snapshot.html });

      if (pages.length % 10 === 0) {
        emitProgress(`Rendered ${pages.length} pages`, pages.length, null);
      }
    } finally {
      await page.close().catch(() => {});
    }
  }

  return { pages };
}

async function capturePage(page, currentUrl, settings) {
  const response = await page.goto(currentUrl, {
    waitUntil: "domcontentloaded",
    timeout: 20_000,
  });

  if (response && response.status() >= 400) {
    return null;
  }

  await page.waitForLoadState("networkidle", { timeout: 5_000 }).catch(() => {});

  const snapshot = await page.evaluate(() => ({
    url: window.location.href,
    html: document.documentElement.outerHTML,
    links: Array.from(document.querySelectorAll("a[href]"), (anchor) => anchor.href),
  }));

  const resolvedUrl = new URL(snapshot.url);
  if (!sameDomain(resolvedUrl, settings)) {
    return null;
  }
  if (!withinBasePath(resolvedUrl, settings)) {
    return null;
  }
  if (skipUrl(resolvedUrl, settings)) {
    return null;
  }

  const links = snapshot.links
    .map((href) => resolveLink(href))
    .filter(Boolean)
    .filter((href) => {
      const url = new URL(href);
      return sameDomain(url, settings) && withinBasePath(url, settings) && !skipUrl(url, settings);
    });

  return {
    url: resolvedUrl.toString(),
    html: snapshot.html,
    links,
  };
}

function buildSettings(input) {
  const seedUrl = new URL(input.url);
  return {
    domain: seedUrl.hostname.toLowerCase(),
    basePath: computeBasePath(seedUrl.pathname),
    crawlDelayMs: input.crawl_delay_ms,
    skipExtensions: input.skip_extensions,
    skipQueryPatterns: input.skip_query_patterns,
    excludePathPrefixes: input.exclude_path_prefixes,
    maxPages: Number.isInteger(input.max_pages) ? input.max_pages : null,
  };
}

function canCrawlMorePages(settings, crawledPages) {
  return settings.maxPages === null || crawledPages < settings.maxPages;
}

function resolveLink(href) {
  if (!href) {
    return null;
  }

  const trimmed = href.trim();
  if (!trimmed || trimmed.startsWith("#")) {
    return null;
  }

  const lower = trimmed.toLowerCase();
  if (["javascript:", "mailto:", "tel:", "data:"].some((prefix) => lower.startsWith(prefix))) {
    return null;
  }

  const [withoutFragment] = trimmed.split("#", 1);
  return withoutFragment || null;
}

function normalizeUrl(url) {
  try {
    const parsed = new URL(url);
    const path = parsed.pathname.replace(/\/$/, "") || "/";
    return `${parsed.protocol}//${parsed.hostname.toLowerCase()}${path}`;
  } catch {
    return url;
  }
}

function sameDomain(url, settings) {
  return url.hostname.toLowerCase() === settings.domain;
}

function withinBasePath(url, settings) {
  if (settings.basePath === "/") {
    return true;
  }

  return url.pathname.toLowerCase().startsWith(settings.basePath.toLowerCase());
}

function skipUrl(url, settings) {
  const path = url.pathname.toLowerCase();

  if (settings.skipExtensions.some((extension) => path.endsWith(extension))) {
    return true;
  }

  const query = url.searchParams.toString();
  if (settings.skipQueryPatterns.some((pattern) => query.includes(pattern))) {
    return true;
  }

  if (/\/(assets|static|images|downloads|uploads|feeds?|api\/v\d)/.test(path)) {
    return true;
  }

  return settings.excludePathPrefixes.some((prefix) => path.startsWith(prefix.toLowerCase()));
}

function computeBasePath(path) {
  const clean = path.replace(/\/$/, "");
  if (!clean || clean === "/") {
    return "/";
  }

  const segments = clean.replace(/^\//, "").split("/");
  if (segments.length === 1) {
    return clean;
  }

  const parts = clean.split("/");
  parts.pop();
  return parts.join("/") || "/";
}

async function readInput() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return JSON.parse(chunks.join(""));
}

function emitProgress(message, current = null, total = null) {
  emit({ type: "progress", message, current, total });
}

function emit(event) {
  process.stdout.write(`${JSON.stringify(event)}\n`);
}

function wait(durationMs) {
  return new Promise((resolve) => setTimeout(resolve, durationMs));
}
