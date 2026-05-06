import dotenv from 'dotenv';
import * as Sentry from '@sentry/node';
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';

dotenv.config();

const serviceName = process.env.OTEL_SERVICE_NAME ?? 'moya-backend';
const otlpEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
const otelEnabled = process.env.OTEL_ENABLED === 'true' || Boolean(otlpEndpoint);
const sentryDsn = process.env.SENTRY_DSN;

let sdk = null;

if (sentryDsn) {
  Sentry.init({
    dsn: sentryDsn,
    environment: process.env.NODE_ENV ?? 'development',
    tracesSampleRate: Number(process.env.SENTRY_TRACES_SAMPLE_RATE ?? 0.2),
  });
  console.log('[APM] Sentry initialized');
}

if (otelEnabled) {
  sdk = new NodeSDK({
    serviceName,
    traceExporter: new OTLPTraceExporter(
      otlpEndpoint ? { url: otlpEndpoint } : undefined,
    ),
    instrumentations: [
      getNodeAutoInstrumentations({
        '@opentelemetry/instrumentation-fs': {
          enabled: false,
        },
      }),
    ],
  });

  try {
    await sdk.start();
    console.log(`[APM] OpenTelemetry initialized for ${serviceName}`);
  } catch (error) {
    console.error('[APM] OpenTelemetry init failed:', error);
  }
}

async function shutdownApm(signal) {
  try {
    await sdk?.shutdown();
    await Sentry.close(2000);
  } catch (error) {
    console.error(`[APM] shutdown failed after ${signal}:`, error);
  }
}

process.once('SIGTERM', () => {
  void shutdownApm('SIGTERM');
});

process.once('SIGINT', () => {
  void shutdownApm('SIGINT');
});
