// Cloudflare Worker: sube y sirve fotos desde R2 (San Valentín)
// Variables: SUPABASE_URL, SUPABASE_ANON_KEY  |  Binding R2: PHOTOS
export default {
  async fetch(req, env) {
    const u = new URL(req.url);
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Authorization,Content-Type",
      "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    };
    if (req.method === "OPTIONS") return new Response(null, { headers: cors });

    if (req.method === "POST" && u.pathname === "/upload") {
      // Solo usuarios con sesión válida de Supabase pueden subir
      const r = await fetch(env.SUPABASE_URL + "/auth/v1/user", {
        headers: { Authorization: req.headers.get("Authorization") || "", apikey: env.SUPABASE_ANON_KEY },
      });
      if (!r.ok) return new Response("No autorizado", { status: 401, headers: cors });
      const { id } = await r.json();
      if (req.headers.get("Content-Type") !== "image/jpeg")
        return new Response("Solo JPEG", { status: 415, headers: cors });
      const buf = await req.arrayBuffer();
      if (buf.byteLength < 100 || buf.byteLength > 300000)
        return new Response("Foto muy grande", { status: 413, headers: cors });
      const key = `${id}/${Date.now()}.jpg`;
      await env.PHOTOS.put(key, buf, { httpMetadata: { contentType: "image/jpeg" } });
      return Response.json({ url: `${u.origin}/img/${key}` }, { headers: cors });
    }

    if (req.method === "GET" && u.pathname.startsWith("/img/")) {
      const o = await env.PHOTOS.get(decodeURIComponent(u.pathname.slice(5)));
      if (!o) return new Response("No existe", { status: 404 });
      return new Response(o.body, {
        headers: {
          "Content-Type": "image/jpeg",
          "Cache-Control": "public, max-age=31536000, immutable",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }
    return new Response("San Valentín · fotos", { headers: cors });
  },
};
