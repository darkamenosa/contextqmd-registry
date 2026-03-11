#!/usr/bin/env node

const accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
const apiToken = process.env.CLOUDFLARE_API_TOKEN;

if (!accountId || !apiToken) {
  console.error("Missing CLOUDFLARE_ACCOUNT_ID or CLOUDFLARE_API_TOKEN");
  process.exit(1);
}

const args = parseArgs(process.argv.slice(2));
if (!args.url) {
  printUsage();
  process.exit(1);
}

const endpoint = `https://api.cloudflare.com/client/v4/accounts/${accountId}/browser-rendering/markdown`;
const payload = buildPayload(args);

try {
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok || data.success === false) {
    console.error(JSON.stringify({ status: response.status, data }, null, 2));
    process.exit(1);
  }

  if (args.json) {
    console.log(JSON.stringify(data, null, 2));
    process.exit(0);
  }

  const markdown = typeof data.result === "string" ? data.result : "";
  if (!markdown) {
    console.error("Cloudflare returned no markdown result");
    process.exit(1);
  }

  console.log(args.preview ? markdown.slice(0, args.preview) : markdown);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}

function parseArgs(argv) {
  const parsed = {
    preview: null,
    json: false,
    waitUntil: "domcontentloaded",
    timeout: 30_000,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    switch (arg) {
      case "--json":
        parsed.json = true;
        break;
      case "--preview":
        parsed.preview = Number(argv[++index]);
        break;
      case "--wait-until":
        parsed.waitUntil = argv[++index];
        break;
      case "--timeout":
        parsed.timeout = Number(argv[++index]);
        break;
      case "--help":
        printUsage();
        process.exit(0);
        break;
      default:
        if (!parsed.url) {
          parsed.url = arg;
        } else {
          throw new Error(`Unknown argument: ${arg}`);
        }
    }
  }

  return parsed;
}

function buildPayload(args) {
  const payload = {
    url: args.url,
    gotoOptions: {
      waitUntil: args.waitUntil,
      timeout: args.timeout,
    },
  };

  return payload;
}

function printUsage() {
  console.log(`Usage:
  node script/cloudflare/markdown_probe.mjs <url> [--json]
  node script/cloudflare/markdown_probe.mjs <url> --wait-until networkidle0 --timeout 45000

Environment:
  CLOUDFLARE_ACCOUNT_ID
  CLOUDFLARE_API_TOKEN`);
}
