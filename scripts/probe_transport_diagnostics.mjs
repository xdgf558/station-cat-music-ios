// Test-only transport diagnostics for the pinned local fixture. Never log messages,
// URLs, headers, bodies, credentials, SQL, or stacks from an underlying error.
import {subscribe} from 'node:diagnostics_channel';
const codes = new Set(['ECONNRESET','ECONNREFUSED','ETIMEDOUT','EPIPE','UND_ERR_SOCKET',
  'UND_ERR_CONNECT_TIMEOUT','UND_ERR_HEADERS_TIMEOUT','UND_ERR_BODY_TIMEOUT','UND_ERR_ABORTED']);
export function transportDiagnostic(error) {
  const chain = [error, error?.cause];
  const code = chain.map(value => value?.code).find(value => codes.has(value)) ?? 'OTHER';
  return {event:'M2_FIXTURE_TRANSPORT_ERROR',code};
}
subscribe('undici:request:error', ({error}) => {
  process.stderr.write(JSON.stringify(transportDiagnostic(error))+'\n');
});
