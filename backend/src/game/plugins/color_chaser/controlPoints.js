'use strict';

// 거점 위치 생성. fantasy_wars 의 deriveControlPointLocations 와 유사한 단순화 버전.
// playable_area 가 없으면 빈 배열을 반환하고, 미션은 비활성화된다.

export function buildControlPoints(playableArea, count) {
  const normalized = normalizeGeoList(playableArea);
  if (normalized.length < 3 || count <= 0) {
    return [];
  }

  const locations = pickSpreadPoints(normalized, count);
  return locations.map((loc, index) => ({
    id: `cp_${index + 1}`,
    displayName: `전화부스 ${index + 1}`,
    location: loc,
    status: 'inactive', // 'inactive' | 'active' | 'claimed' | 'expired'
    activatedAt: null,
    expiresAt: null,
    claimedBy: null,
    claimedAt: null,
  }));
}

function pickSpreadPoints(playableArea, count) {
  const bounds = computeBounds(playableArea);
  const gridSize = Math.max(5, Math.ceil(Math.sqrt(count)) * 3);
  const candidates = [];

  for (let row = 0; row < gridSize; row += 1) {
    for (let col = 0; col < gridSize; col += 1) {
      const lat = bounds.minLat + ((row + 0.5) / gridSize) * (bounds.maxLat - bounds.minLat);
      const lng = bounds.minLng + ((col + 0.5) / gridSize) * (bounds.maxLng - bounds.minLng);
      const candidate = { lat, lng };
      if (pointInPolygon(candidate, playableArea)) {
        candidates.push(candidate);
      }
    }
  }

  if (candidates.length === 0) {
    // playableArea 의 평균점 fallback.
    return [averagePoint(playableArea)];
  }

  // farthest-point sampling 으로 균등 분포 선택.
  const center = averagePoint(candidates);
  const chosen = [closestTo(candidates, center)];
  const remaining = candidates.filter((p) => !samePoint(p, chosen[0]));

  while (chosen.length < count && remaining.length > 0) {
    let bestIndex = 0;
    let bestScore = -1;
    remaining.forEach((cand, idx) => {
      const score = Math.min(...chosen.map((p) => distSq(cand, p)));
      if (score > bestScore) {
        bestScore = score;
        bestIndex = idx;
      }
    });
    chosen.push(remaining.splice(bestIndex, 1)[0]);
  }

  return chosen;
}

function computeBounds(points) {
  return points.reduce(
    (acc, p) => ({
      minLat: Math.min(acc.minLat, p.lat),
      maxLat: Math.max(acc.maxLat, p.lat),
      minLng: Math.min(acc.minLng, p.lng),
      maxLng: Math.max(acc.maxLng, p.lng),
    }),
    {
      minLat: points[0].lat,
      maxLat: points[0].lat,
      minLng: points[0].lng,
      maxLng: points[0].lng,
    },
  );
}

function pointInPolygon(point, polygon) {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i, i += 1) {
    const xi = polygon[i].lng;
    const yi = polygon[i].lat;
    const xj = polygon[j].lng;
    const yj = polygon[j].lat;
    const intersects =
      yi > point.lat !== yj > point.lat &&
      point.lng < ((xj - xi) * (point.lat - yi)) / ((yj - yi) || Number.EPSILON) + xi;
    if (intersects) inside = !inside;
  }
  return inside;
}

function averagePoint(points) {
  const total = points.reduce(
    (acc, p) => ({ lat: acc.lat + p.lat, lng: acc.lng + p.lng }),
    { lat: 0, lng: 0 },
  );
  return { lat: total.lat / points.length, lng: total.lng / points.length };
}

function distSq(a, b) {
  return (a.lat - b.lat) ** 2 + (a.lng - b.lng) ** 2;
}

function closestTo(points, target) {
  return points.reduce(
    (best, p) => (distSq(p, target) < distSq(best, target) ? p : best),
    points[0],
  );
}

function samePoint(a, b) {
  return a.lat === b.lat && a.lng === b.lng;
}

function normalizeGeoList(points) {
  if (!Array.isArray(points)) return [];
  return points
    .map((p) => {
      const lat = Number(p?.lat ?? p?.latitude);
      const lng = Number(p?.lng ?? p?.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
      return { lat, lng };
    })
    .filter(Boolean);
}
