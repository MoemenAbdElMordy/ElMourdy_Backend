import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { test } from "node:test";
import worker from "./index.js";

const secret = "test-secret";
const payload = Buffer.from(JSON.stringify({
  asset_id: 8,
  prefix: "videos/test/hls",
  expires_at: Math.floor(Date.now() / 1000) + 60,
})).toString("base64url");
const signature = createHmac("sha256", secret).update(payload).digest("hex");
const url = `https://example.test/8/${payload}.${signature}/720p/segment_00000.ts`;

function environment(get) {
  return {
    VIDEO_PLAYBACK_SECRET: secret,
    ALLOWED_ORIGIN: "https://mourdy.com",
    VIDEOS: { get },
  };
}

function object(range) {
  return {
    range,
    size: 10,
    body: "video-data",
    httpEtag: '"test"',
    writeHttpMetadata() {},
  };
}

test("full media requests return 200 without asking R2 for a range", async () => {
  let options;
  const response = await worker.fetch(new Request(url), environment((_key, value) => {
    options = value;
    return object(undefined);
  }));
  assert.equal(options, undefined);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-range"), null);
  assert.equal(await response.text(), "video-data");
});

test("range requests return 206 when R2 serves a range", async () => {
  let options;
  const response = await worker.fetch(new Request(url, {
    headers: { Range: "bytes=0-3" },
  }), environment((_key, value) => {
    options = value;
    return object({ offset: 0, length: 4 });
  }));
  assert.ok(options?.range);
  assert.equal(response.status, 206);
  assert.equal(response.headers.get("content-range"), "bytes 0-3/10");
});
