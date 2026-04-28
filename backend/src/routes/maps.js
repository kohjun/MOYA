// src/routes/maps.js
//
// Naver Static Map API 프록시.
// client_id / client_secret 을 클라이언트에 노출하지 않기 위해 백엔드에서 호출 후 PNG 그대로 stream.
//
// ENV 필요:
//   NAVER_MAP_CLIENT_ID
//   NAVER_MAP_CLIENT_SECRET
//
// 클라이언트 호출 예:
//   GET /maps/static?lat=37.5665&lng=126.9780&zoom=16&w=600&h=400
//
// 응답: image/png

const NAVER_STATIC_MAP_URL = 'https://maps.apigw.ntruss.com/map-static/v2/raster';

const clamp = (n, min, max) => Math.max(min, Math.min(max, n));

export default async function mapRoutes(fastify) {
  fastify.get('/static', async (req, reply) => {
    const clientId = process.env.NAVER_MAP_CLIENT_ID;
    const clientSecret = process.env.NAVER_MAP_CLIENT_SECRET;
    if (!clientId || !clientSecret) {
      return reply.status(500).send({ error: 'STATIC_MAP_NOT_CONFIGURED' });
    }

    const lat = Number(req.query.lat);
    const lng = Number(req.query.lng);
    const zoom = clamp(parseInt(req.query.zoom ?? '16', 10), 1, 20);
    const w = clamp(parseInt(req.query.w ?? '600', 10), 100, 1024);
    const h = clamp(parseInt(req.query.h ?? '400', 10), 100, 1024);

    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return reply.status(400).send({ error: 'INVALID_COORDS' });
    }

    const url = `${NAVER_STATIC_MAP_URL}?w=${w}&h=${h}&center=${lng},${lat}&level=${zoom}&format=png`;

    try {
      const upstream = await fetch(url, {
        headers: {
          'X-NCP-APIGW-API-KEY-ID': clientId,
          'X-NCP-APIGW-API-KEY': clientSecret,
        },
      });

      if (!upstream.ok) {
        const body = await upstream.text();
        req.log?.warn?.({ status: upstream.status, body }, '[StaticMap] upstream failed');
        return reply
          .status(upstream.status)
          .send({ error: 'STATIC_MAP_UPSTREAM_FAILED', status: upstream.status });
      }

      const buf = Buffer.from(await upstream.arrayBuffer());
      reply
        .header('Content-Type', 'image/png')
        .header('Cache-Control', 'public, max-age=86400'); // 24h cache (지도 타일은 자주 안 변함)
      return reply.send(buf);
    } catch (err) {
      req.log?.error?.(err, '[StaticMap] fetch failed');
      return reply.status(502).send({ error: 'STATIC_MAP_FETCH_FAILED' });
    }
  });
}
