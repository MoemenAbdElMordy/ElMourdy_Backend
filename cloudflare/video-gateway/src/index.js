const encoder = new TextEncoder();

function decodeBase64Url(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padding = "=".repeat((4 - normalized.length % 4) % 4);
  return JSON.parse(atob(normalized + padding));
}

async function validSignature(payload, supplied, secret) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  const expected = Array.from(new Uint8Array(signature), byte => byte.toString(16).padStart(2, "0")).join("");
  if (expected.length !== supplied.length) return false;
  let difference = 0;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= expected.charCodeAt(index) ^ supplied.charCodeAt(index);
  }
  return difference === 0;
}

function responseHeaders(request, env, object) {
  const origin = request.headers.get("Origin");
  const allowedOrigin = origin === env.ALLOWED_ORIGIN ? origin : env.ALLOWED_ORIGIN;
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("access-control-allow-origin", allowedOrigin);
  headers.set("vary", "Origin");
  headers.set("cache-control", "private, max-age=60");
  return headers;
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "access-control-allow-origin": env.ALLOWED_ORIGIN,
          "access-control-allow-methods": "GET, HEAD, OPTIONS",
          "access-control-allow-headers": "Range"
        }
      });
    }
    if (!env.VIDEO_PLAYBACK_SECRET) return new Response("Gateway secret is missing", { status: 500 });

    const parts = new URL(request.url).pathname.split("/").filter(Boolean);
    if (parts.length < 4) return new Response("Not found", { status: 404 });
    const [assetId, token, ...mediaPath] = parts;
    const [encoded, suppliedSignature] = token.split(".", 2);
    if (!encoded || !suppliedSignature || !(await validSignature(encoded, suppliedSignature, env.VIDEO_PLAYBACK_SECRET))) {
      return new Response("Unauthorized", { status: 401 });
    }

    let payload;
    try {
      payload = decodeBase64Url(encoded);
    } catch {
      return new Response("Unauthorized", { status: 401 });
    }
    if (String(payload.asset_id) !== assetId || Number(payload.expires_at) < Math.floor(Date.now() / 1000)) {
      return new Response("Unauthorized", { status: 401 });
    }

    const key = `${payload.prefix}/${mediaPath.join("/")}`;
    if (key.includes("..")) return new Response("Invalid path", { status: 400 });
    const object = await env.VIDEOS.get(key, { range: request.headers });
    if (!object) return new Response("Not found", { status: 404 });

    return new Response(request.method === "HEAD" ? null : object.body, {
      status: object.range ? 206 : 200,
      headers: responseHeaders(request, env, object)
    });
  }
};
