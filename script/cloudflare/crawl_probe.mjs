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

const endpoint = `https://api.cloudflare.com/client/v4/accounts/${accountId}/browser-rendering/crawl`;
const payload = buildPayload(args);

try {
  console.error(`Submitting crawl for ${args.url}`);
  const created = await cfFetch(endpoint, {
    method: "POST",
    headers: jsonHeaders(),
    body: JSON.stringify(payload),
  });

  const jobId =
    (typeof created?.result === "string" ? created.result : null) ||
    created?.result?.id ||
    created?.result?.jobId ||
    created?.result?.job_id;
  if (!jobId) {
    throw new Error(`Unexpected create response: ${JSON.stringify(created, null, 2)}`);
  }

  console.log(JSON.stringify({ type: "created", jobId, payload }, null, 2));

  const result = await waitForCompletion(`${endpoint}/${jobId}`, {
    pollIntervalMs: args.pollIntervalMs,
    timeoutMs: args.timeoutMs,
  });

  const completedResult = extractStatus(result) === "completed"
    ? await fetchCompletedResult(`${endpoint}/${jobId}`, args.sampleRecords)
    : result;

  const usage = extractUsage(completedResult);
  console.log(
    JSON.stringify(
      {
        type: "completed",
        jobId,
        status: extractStatus(completedResult),
        counts: extractCounts(completedResult),
        usage,
        estimatedCostUsd: usage ? estimateBrowserRenderingCostUsd(usage.browserSeconds, args.plan) : null,
        sampleRecords: extractRecords(completedResult).slice(0, args.sampleRecords),
      },
      null,
      2
    )
  );
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}

function parseArgs(argv) {
  const parsed = {
    render: true,
    limit: 20,
    depth: 2,
    formats: ["markdown"],
    plan: "paid",
    pollIntervalMs: 5_000,
    timeoutMs: 5 * 60_000,
    sampleRecords: 3,
    source: "all",
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    switch (arg) {
      case "--url":
        parsed.url = argv[++index];
        break;
      case "--limit":
        parsed.limit = Number(argv[++index]);
        break;
      case "--depth":
        parsed.depth = Number(argv[++index]);
        break;
      case "--formats":
        parsed.formats = argv[++index].split(",").map((value) => value.trim()).filter(Boolean);
        break;
      case "--render":
        parsed.render = argv[++index] !== "false";
        break;
      case "--plan":
        parsed.plan = argv[++index];
        break;
      case "--poll-interval-ms":
        parsed.pollIntervalMs = Number(argv[++index]);
        break;
      case "--timeout-ms":
        parsed.timeoutMs = Number(argv[++index]);
        break;
      case "--sample-records":
        parsed.sampleRecords = Number(argv[++index]);
        break;
      case "--source":
        parsed.source = argv[++index];
        break;
      case "--include-pattern":
        parsed.includePatterns ||= [];
        parsed.includePatterns.push(argv[++index]);
        break;
      case "--exclude-pattern":
        parsed.excludePatterns ||= [];
        parsed.excludePatterns.push(argv[++index]);
        break;
      case "--help":
        printUsage();
        process.exit(0);
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return parsed;
}

function buildPayload(args) {
  const payload = {
    url: args.url,
    limit: args.limit,
    depth: args.depth,
    formats: args.formats,
    render: args.render,
    source: args.source,
  };

  if (args.includePatterns?.length || args.excludePatterns?.length) {
    payload.options = {};
    if (args.includePatterns?.length) {
      payload.options.includePatterns = args.includePatterns;
    }
    if (args.excludePatterns?.length) {
      payload.options.excludePatterns = args.excludePatterns;
    }
  }

  return payload;
}

async function waitForCompletion(jobUrl, { pollIntervalMs, timeoutMs }) {
  const startedAt = Date.now();
  const statusUrl = new URL(jobUrl);
  statusUrl.searchParams.set("limit", "1");

  while (Date.now() - startedAt < timeoutMs) {
    let response;
    try {
      response = await cfFetch(statusUrl.toString(), {
        method: "GET",
        headers: authHeaders(),
      });
    } catch (error) {
      if (isRetriablePollError(error)) {
        await wait(pollIntervalMs);
        continue;
      }

      throw error;
    }

    const status = extractStatus(response);
    if (["completed", "failed", "cancelled", "timed_out", "limit_exceeded"].includes(status)) {
      return response;
    }

    await wait(pollIntervalMs);
  }

  throw new Error("Crawl job did not complete before timeout");
}

async function fetchCompletedResult(jobUrl, limit) {
  const resultsUrl = new URL(jobUrl);
  resultsUrl.searchParams.set("limit", String(limit));
  resultsUrl.searchParams.set("status", "completed");

  return cfFetch(resultsUrl.toString(), {
    method: "GET",
    headers: authHeaders(),
  });
}

function extractStatus(response) {
  return (
    response?.result?.status ||
    response?.status ||
    response?.result?.job?.status ||
    "unknown"
  );
}

function extractCounts(response) {
  const result = response?.result || {};
  return {
    records: Array.isArray(result.records) ? result.records.length : result.recordsCount ?? null,
    skipped: result.skippedCount ?? null,
    discovered: result.discoveredCount ?? null,
  };
}

function extractRecords(response) {
  const result = response?.result || {};
  return Array.isArray(result.records) ? result.records : [];
}

function extractUsage(response) {
  const result = response?.result || {};
  const browserSeconds =
    result.browserSecondsUsed ??
    result.browser_seconds_used ??
    result.usage?.browserSeconds ??
    result.usage?.browser_seconds;

  if (browserSeconds == null) {
    return null;
  }

  return {
    browserSeconds,
    browserHours: browserSeconds / 3600,
  };
}

function estimateBrowserRenderingCostUsd(browserSeconds, plan) {
  if (browserSeconds == null) {
    return null;
  }

  if (plan === "free") {
    return 0;
  }

  return Number(((browserSeconds / 3600) * 0.09).toFixed(4));
}

async function cfFetch(url, init) {
  const response = await fetch(url, init);
  const data = await response.json().catch(() => ({}));

  if (!response.ok || data.success === false) {
    const error = new Error(JSON.stringify({ status: response.status, data }, null, 2));
    error.responseStatus = response.status;
    error.responseData = data;
    throw error;
  }

  return data;
}

function isRetriablePollError(error) {
  return (
    isPendingJobCreationError(error) ||
    isRateLimitError(error)
  );
}

function isPendingJobCreationError(error) {
  return (
    error &&
    error.responseStatus === 404 &&
    Array.isArray(error.responseData?.errors) &&
    error.responseData.errors.some(
      (item) => item?.code === 1001 && item?.message === "Crawl job not found"
    )
  );
}

function isRateLimitError(error) {
  return (
    error &&
    error.responseStatus === 429 &&
    Array.isArray(error.responseData?.errors) &&
    error.responseData.errors.some(
      (item) => item?.code === 2001 && item?.message === "Rate limit exceeded"
    )
  );
}

function authHeaders() {
  return {
    Authorization: `Bearer ${apiToken}`,
  };
}

function jsonHeaders() {
  return {
    ...authHeaders(),
    "Content-Type": "application/json",
  };
}

function wait(durationMs) {
  return new Promise((resolve) => setTimeout(resolve, durationMs));
}

function printUsage() {
  console.log(`Usage:
  node script/cloudflare/crawl_probe.mjs --url https://example.com/docs \\
    [--limit 20] [--depth 2] [--formats markdown] [--render true] [--plan paid]

Environment:
  CLOUDFLARE_ACCOUNT_ID
  CLOUDFLARE_API_TOKEN`);
}
