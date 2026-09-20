import assert from 'node:assert/strict';
import {test} from 'node:test';
import {transportDiagnostic} from './probe_transport_diagnostics.mjs';
test('transport diagnostics only emit fixed error categories, never arbitrary values', () => {
  const privateValue='synthetic-secret-in-url-header-body';
  assert.deepEqual(transportDiagnostic({code:'ECONNRESET',message:privateValue}),
    {event:'M2_FIXTURE_TRANSPORT_ERROR',code:'ECONNRESET'});
  assert.equal(transportDiagnostic({cause:{code:'UND_ERR_SOCKET',stack:privateValue}}).code,'UND_ERR_SOCKET');
  assert.equal(transportDiagnostic({code:privateValue,message:privateValue}).code,'OTHER');
  assert.equal(transportDiagnostic(null).code,'OTHER');
});
