import { SpanStatusCode, trace } from '@opentelemetry/api';
import * as Sentry from '@sentry/node';

const tracer = trace.getTracer('moya-fantasy-wars');

export async function traceAsync(name, attributes, action) {
  return tracer.startActiveSpan(
    sanitizeName(name),
    { attributes: sanitizeAttributes(attributes) },
    async (span) => {
      try {
        const result = await action(span);
        span.setAttribute('result.ok', true);
        return result;
      } catch (error) {
        span.setAttribute('result.ok', false);
        span.setAttribute('error.type', error?.name ?? 'Error');
        span.recordException(error);
        span.setStatus({
          code: SpanStatusCode.ERROR,
          message: error?.message,
        });
        if (process.env.SENTRY_DSN) {
          Sentry.captureException(error);
        }
        throw error;
      } finally {
        span.end();
      }
    },
  );
}

export function markResult(span, result) {
  if (!span || !result || typeof result !== 'object') {
    return;
  }

  const ok = result.ok !== false && !result.error;
  span.setAttribute('result.ok', ok);
  if (result.error) {
    span.setAttribute('result.error', sanitizeValue(result.error));
    span.setStatus({
      code: SpanStatusCode.ERROR,
      message: sanitizeValue(result.error),
    });
  }
  if (result.distanceMeters != null) {
    span.setAttribute('fw.distance_meters', Number(result.distanceMeters));
  }
  if (result.proximitySource) {
    span.setAttribute(
      'fw.proximity_source',
      sanitizeValue(result.proximitySource),
    );
  }
  if (result.bleConfirmed != null) {
    span.setAttribute('fw.ble_confirmed', Boolean(result.bleConfirmed));
  }
}

function sanitizeName(value) {
  return String(value ?? 'trace')
    .replace(/[^a-zA-Z0-9_.-]/g, '_')
    .slice(0, 120);
}

function sanitizeAttributes(attributes = {}) {
  return Object.fromEntries(
    Object.entries(attributes)
      .filter(([, value]) => value != null)
      .map(([key, value]) => [sanitizeKey(key), sanitizeValue(value)]),
  );
}

function sanitizeKey(value) {
  const key = String(value ?? 'key')
    .replace(/[^a-zA-Z0-9_.-]/g, '_')
    .slice(0, 80);
  return key || 'key';
}

function sanitizeValue(value) {
  if (typeof value === 'number' || typeof value === 'boolean') {
    return value;
  }
  return String(value).replace(/[\r\n\t]/g, ' ').slice(0, 160);
}
