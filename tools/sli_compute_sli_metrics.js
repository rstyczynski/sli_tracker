#!/usr/bin/env node
"use strict";

/**
 * SLI-20: Compute rolling-window SLI from OCI Monitoring metrics.
 *
 * This tool supports a fixture-first workflow so unit/integration tests do not
 * require OCI credentials.
 *
 * Modes:
 * - Fixture mode (recommended for tests): --input-file <json>
 * - Live mode (OCI Monitoring via Node SDK): supported via --oci-config-file/--oci-profile
 */

const fs = require("fs");
const path = require("path");

function nowIso() {
  return new Date().toISOString();
}

function die(msg, code = 2) {
  process.stderr.write(`${msg}\n`);
  process.exit(code);
}

function usage() {
  return `Usage: tools/sli_compute_sli_metrics.js [OPTIONS]

Compute SLI as a success ratio from metric 'outcome' (1=success, 0=other)
over a rolling window (default: 30 days), optionally filtered by dimensions.

Options:
  --window-days N           Window length in days (default: 30)
  --namespace NAME          Monitoring namespace (default: sli_tracker)
  --metric-name NAME        Metric name (default: outcome)
  --compartment-id OCID     Compartment OCID (live mode)
  --dimension k=v           Dimension filter (repeatable)
  --output json|text        Output format (default: json)
  --mql-resolution RES      MQL resolution, e.g. 1m, 5m, 1h, 1d (default: 1d)
  --oci-auth MODE           OCI auth mode: config|instance_principal (default: config)
  --oci-config-file PATH    OCI config file (default: ~/.oci/config)
  --oci-profile NAME        OCI profile (default: DEFAULT)
  --region-id ID            Force region id (e.g. eu-zurich-1). Optional.
  --persist TARGETS         Optional: log,metric,log,metric (default: none)
  --persist-log-id OCID     OCI Log OCID used for persistence (when TARGET includes log)
  --persist-metric-namespace NAME  Metric namespace for persistence (default: sli_tracker)
  --input-file PATH         Fixture JSON file (no OCI calls)
  --help                    Show help

Fixture file schema:
  {
    "buckets": [
      {"sum": <number>, "count": <number>},
      ...
    ]
  }
`;
}

function parseArgs(argv) {
  const out = {
    windowDays: 30,
    namespace: "sli_tracker",
    metricName: "outcome",
    compartmentId: "",
    dimensions: {},
    output: "json",
    inputFile: "",
    mqlResolution: "1d",
    ociAuth: "config",
    ociConfigFile: "~/.oci/config",
    ociProfile: "DEFAULT",
    regionId: "",
    persist: "",
    persistLogId: "",
    persistMetricNamespace: "sli_tracker",
    help: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--help" || a === "-h") out.help = true;
    else if (a === "--window-days") out.windowDays = Number(argv[++i]);
    else if (a === "--namespace") out.namespace = String(argv[++i] || "");
    else if (a === "--metric-name") out.metricName = String(argv[++i] || "");
    else if (a === "--compartment-id") out.compartmentId = String(argv[++i] || "");
    else if (a === "--oci-auth") out.ociAuth = String(argv[++i] || "config");
    else if (a === "--oci-config-file") out.ociConfigFile = String(argv[++i] || "");
    else if (a === "--oci-profile") out.ociProfile = String(argv[++i] || "");
    else if (a === "--region-id") out.regionId = String(argv[++i] || "");
    else if (a === "--persist") out.persist = String(argv[++i] || "");
    else if (a === "--persist-log-id") out.persistLogId = String(argv[++i] || "");
    else if (a === "--persist-metric-namespace") out.persistMetricNamespace = String(argv[++i] || "");
    else if (a === "--dimension") {
      const kv = String(argv[++i] || "");
      const idx = kv.indexOf("=");
      if (idx <= 0) die(`Invalid --dimension '${kv}' (expected key=value)`);
      const k = kv.slice(0, idx);
      const v = kv.slice(idx + 1);
      out.dimensions[k] = v;
    } else if (a === "--output") out.output = String(argv[++i] || "json");
    else if (a === "--mql-resolution") out.mqlResolution = String(argv[++i] || "1d");
    else if (a === "--input-file") out.inputFile = String(argv[++i] || "");
    else die(`Unknown arg: ${a}`);
  }
  return out;
}

function validateMqlResolution(res) {
  const r = String(res || "").trim();
  if (!r) die("--mql-resolution must be non-empty (e.g. 5m, 1h, 1d)");
  if (!/^[0-9]+[smhdw]$/.test(r)) {
    die(`Invalid --mql-resolution '${r}' (expected: <number><s|m|h|d|w>, e.g. 5m)`);
  }
  return r;
}

function regionIdFromProvider(provider) {
  if (!provider) return "";
  try {
    if (typeof provider.getRegion === "function") {
      const r = provider.getRegion();
      if (!r) return "";
      // Region object in the SDK typically has `regionId`; keep fallbacks defensive.
      return r.regionId || r.regionIdentifier || r.regionCode || String(r);
    }
  } catch (_) {
    // ignore
  }
  return "";
}

function expandHome(p) {
  if (!p) return p;
  if (p === "~") return process.env.HOME || p;
  if (p.startsWith("~/")) return path.join(process.env.HOME || "", p.slice(2));
  return p;
}

/** Resolve profile for OCI SDK: empty string from shell must not silently become DEFAULT if env sets OCI_CLI_PROFILE. */
function effectiveOciProfile(args) {
  const raw = args.ociProfile;
  const fromEnv = String(process.env.OCI_CLI_PROFILE || process.env.OCI_PROFILE || "").trim();
  if (raw === undefined || raw === null) return fromEnv || "DEFAULT";
  const s = String(raw).trim();
  if (s === "") return fromEnv || "DEFAULT";
  return s;
}

function prepareConfigFileForSdk(configFilePath) {
  const p = expandHome(configFilePath);
  const raw = fs.readFileSync(p, "utf8");
  const home = process.env.HOME || "";

  // Some repo tooling uses placeholders in ~/.oci trees; the SDK won't expand them.
  const patched = raw.replaceAll("${{HOME}}", home).replaceAll("${HOME}", home);
  if (patched === raw) return p;

  const tmp = fs.mkdtempSync(path.join(require("os").tmpdir(), "sli-oci-config-"));
  const outPath = path.join(tmp, "config");
  fs.writeFileSync(outPath, patched, "utf8");
  return outPath;
}

function readProfileField(configPath, profile, field) {
  const raw = fs.readFileSync(configPath, "utf8");
  const lines = raw.split(/\r?\n/);
  let inProfile = false;
  const header = `[${profile}]`;
  for (const line of lines) {
    const t = line.trim();
    if (!t) continue;
    if (t.startsWith("[") && t.endsWith("]")) {
      inProfile = t === header;
      continue;
    }
    if (!inProfile) continue;
    const idx = t.indexOf("=");
    if (idx <= 0) continue;
    const k = t.slice(0, idx).trim();
    const v = t.slice(idx + 1).trim();
    if (k === field) return v;
  }
  return "";
}

async function createAuthProvider(common, args) {
  const mode = String(args.ociAuth || "config").toLowerCase();

  if (mode === "instance_principal" || mode === "instance-principal" || mode === "ip") {
    const builder = new common.InstancePrincipalsAuthenticationDetailsProviderBuilder();
    const provider = await builder.build();
    return { provider, configFile: "" };
  }

  if (mode !== "config") {
    die(`Unsupported --oci-auth '${args.ociAuth}' (expected: config|instance_principal)`);
  }

  const configFile = prepareConfigFileForSdk(args.ociConfigFile);
  const profile = effectiveOciProfile(args);
  const stf = readProfileField(configFile, profile, "security_token_file");
  if (stf) {
    const p = new common.SessionAuthDetailProvider(configFile, profile);
    // The SDK reads the token file as-is; ensure we strip trailing newlines/whitespace.
    const tokenPath = expandHome(stf);
    if (tokenPath) {
      const token = fs.readFileSync(tokenPath, "utf8").trim();
      if (token) p.sessionToken = token;
    }
    return { provider: p, configFile };
  }
  return { provider: new common.ConfigFileAuthenticationDetailsProvider(configFile, profile), configFile };
}

function buildDimensionPredicate(dimensions) {
  const keys = Object.keys(dimensions || {});
  if (keys.length === 0) return "";
  const parts = keys
    .sort()
    .map((k) => `${k} = "${String(dimensions[k]).replaceAll('"', '\\"')}"`);
  return `{${parts.join(", ")}}`;
}

function computeFromBuckets(buckets) {
  let success = 0;
  let total = 0;
  for (const b of buckets) {
    const s = Number(b.sum);
    const c = Number(b.count);
    if (!Number.isFinite(s) || !Number.isFinite(c)) die("Invalid bucket numbers in input");
    success += s;
    total += c;
  }
  if (total <= 0) {
    return { success_count: 0, total_count: 0, sli: null };
  }
  return { success_count: success, total_count: total, sli: success / total };
}

function formatText(result) {
  const sliStr = result.sli === null ? "n/a" : result.sli.toFixed(6);
  return [
    `sli=${sliStr}`,
    `success_count=${result.success_count}`,
    `total_count=${result.total_count}`,
    `window_days=${result.window_days}`,
    `namespace=${result.namespace}`,
    `metric_name=${result.metric_name}`,
    `dimensions=${JSON.stringify(result.dimensions)}`,
  ].join("\n");
}

async function liveQueryBuckets(args) {
  // Lazy requires so fixture mode has no SDK dependency.
  // eslint-disable-next-line global-require
  const common = require("oci-common");
  // eslint-disable-next-line global-require
  const monitoring = require("oci-monitoring");

  const { provider, configFile } = await createAuthProvider(common, args);
  const client = new monitoring.MonitoringClient({ authenticationDetailsProvider: provider });
  // Avoid subtle Region object incompatibilities across SDK packages by forcing regionId explicitly.
  const regionId =
    args.regionId ||
    (configFile ? readProfileField(configFile, effectiveOciProfile(args), "region") : "") ||
    regionIdFromProvider(provider) ||
    process.env.OCI_REGION;
  if (regionId) client.regionId = regionId;

  const endTime = new Date();
  const startTime = new Date(endTime.getTime() - args.windowDays * 24 * 60 * 60 * 1000);

  const pred = buildDimensionPredicate(args.dimensions);
  const res = validateMqlResolution(args.mqlResolution || "1d");
  const sumQuery = `${args.metricName}[${res}]${pred}.sum()`;
  const countQuery = `${args.metricName}[${res}]${pred}.count()`;

  let sumResp;
  let countResp;
  try {
    sumResp = await client.summarizeMetricsData({
      compartmentId: args.compartmentId,
      summarizeMetricsDataDetails: { namespace: args.namespace, query: sumQuery, startTime, endTime },
    });
  } catch (e) {
    const details = {
      op: "summarizeMetricsData(sum)",
      statusCode: e && e.statusCode,
      serviceCode: e && e.serviceCode,
      message: e && e.message,
      query: sumQuery,
      namespace: args.namespace,
      compartmentId: args.compartmentId,
    };
    throw new Error(`OCI Monitoring query failed: ${JSON.stringify(details)}`);
  }

  try {
    countResp = await client.summarizeMetricsData({
      compartmentId: args.compartmentId,
      summarizeMetricsDataDetails: { namespace: args.namespace, query: countQuery, startTime, endTime },
    });
  } catch (e) {
    const details = {
      op: "summarizeMetricsData(count)",
      statusCode: e && e.statusCode,
      serviceCode: e && e.serviceCode,
      message: e && e.message,
      query: countQuery,
      namespace: args.namespace,
      compartmentId: args.compartmentId,
    };
    throw new Error(`OCI Monitoring query failed: ${JSON.stringify(details)}`);
  }

  // The TypeScript SDK returns the response payload under `items` (see client composeResponse bodyKey).
  // Keep fallbacks for alternate shapes to be defensive.
  const sumPoints =
    sumResp.items ||
    (sumResp && sumResp.summarizeMetricsDataResponse && sumResp.summarizeMetricsDataResponse.data) ||
    sumResp.data ||
    [];
  const countPoints =
    countResp.items ||
    (countResp && countResp.summarizeMetricsDataResponse && countResp.summarizeMetricsDataResponse.data) ||
    countResp.data ||
    [];

  function aggTotal(dataArr) {
    let total = 0;
    for (const stream of dataArr || []) {
      const adp = stream.aggregatedDatapoints || stream["aggregated-datapoints"] || [];
      for (const dp of adp) {
        const v = Number(dp.value);
        if (Number.isFinite(v)) total += v;
      }
    }
    return total;
  }

  const successCount = aggTotal(sumPoints);
  const totalCount = aggTotal(countPoints);
  return [{ sum: successCount, count: totalCount }];
}

async function persistSnapshot(args, result) {
  const targets = (args.persist || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  if (targets.length === 0) return;

  // eslint-disable-next-line global-require
  const common = require("oci-common");
  const { provider, configFile } = await createAuthProvider(common, args);
  const regionId =
    args.regionId ||
    (configFile ? readProfileField(configFile, effectiveOciProfile(args), "region") : "") ||
    regionIdFromProvider(provider) ||
    process.env.OCI_REGION;

  const snapshot = {
    source: "sli-tracker/sli_compute_sli_metrics",
    computed_at: nowIso(),
    window_days: result.window_days,
    namespace: result.namespace,
    metric_name: result.metric_name,
    dimensions: result.dimensions,
    sli: result.sli,
    success_count: result.success_count,
    total_count: result.total_count,
  };

  if (targets.includes("log")) {
    if (!args.persistLogId) die("--persist-log-id is required when --persist includes log");
    // eslint-disable-next-line global-require
    const loggingingestion = require("oci-loggingingestion");
    const logClient = new loggingingestion.LoggingClient({ authenticationDetailsProvider: provider });
    if (regionId) logClient.regionId = regionId;

    await logClient.putLogs({
      logId: args.persistLogId,
      putLogsDetails: {
        specversion: "1.0",
        logEntryBatches: [
          {
            source: "sli-tracker/sli_compute_sli_metrics",
            type: "sli-snapshot",
            defaultlogentrytime: snapshot.computed_at,
            entries: [
              {
                id: `sli-snapshot-${Date.now()}`,
                time: snapshot.computed_at,
                data: JSON.stringify(snapshot),
              },
            ],
          },
        ],
      },
    });
  }

  if (targets.includes("metric")) {
    // eslint-disable-next-line global-require
    const monitoring = require("oci-monitoring");
    const monClient = new monitoring.MonitoringClient({ authenticationDetailsProvider: provider });
    if (regionId) monClient.regionId = regionId;
    if (regionId) {
      // PostMetricData requires the telemetry-ingestion endpoint, not the telemetry endpoint.
      monClient.endpoint = `https://telemetry-ingestion.${regionId}.oraclecloud.com`;
    }

    const metricNs = args.persistMetricNamespace || "sli_tracker";
    const compId = args.compartmentId;
    if (!compId) die("--compartment-id is required when --persist includes metric");

    // Persist snapshot SLI ratio as a single datapoint (value in [0,1]).
    const v = result.sli === null ? 0 : Number(result.sli);
    await monClient.postMetricData({
      postMetricDataDetails: {
        metricData: [
          {
            namespace: metricNs,
            name: "sli_ratio",
            compartmentId: compId,
            dimensions: { ...result.dimensions, window_days: String(result.window_days) },
            datapoints: [{ timestamp: snapshot.computed_at, value: v }],
          },
        ],
      },
    });
  }
}

async function main() {
  // Avoid failing hard when stdout is piped to a consumer that exits early (e.g. `... | jq`).
  // This can happen in CI logs; the computed snapshot/persist work may have already succeeded.
  process.stdout.on("error", (err) => {
    if (err && err.code === "EPIPE") process.exit(0);
  });

  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write(usage());
    return;
  }
  if (!Number.isFinite(args.windowDays) || args.windowDays <= 0) die("--window-days must be a positive number");
  if (!args.namespace) die("--namespace is required");
  if (!args.metricName) die("--metric-name is required");
  if (!["json", "text"].includes(args.output)) die("--output must be json|text");

  let buckets = [];
  if (args.inputFile) {
    const p = path.resolve(process.cwd(), args.inputFile);
    const raw = fs.readFileSync(p, "utf8");
    const obj = JSON.parse(raw);
    buckets = Array.isArray(obj.buckets) ? obj.buckets : [];
  } else {
    if (!args.compartmentId) die("--compartment-id is required in live mode (or use --input-file)");
    buckets = await liveQueryBuckets(args);
  }

  const r = computeFromBuckets(buckets);
  const result = {
    window_days: args.windowDays,
    namespace: args.namespace,
    metric_name: args.metricName,
    dimensions: args.dimensions,
    ...r,
  };

  await persistSnapshot(args, result);

  if (args.output === "json") {
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } else {
    process.stdout.write(`${formatText(result)}\n`);
  }
}

main().catch((e) => die(String(e && e.stack ? e.stack : e), 1));

