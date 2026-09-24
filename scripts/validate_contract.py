from pathlib import Path
from copy import deepcopy
import json,base64,hashlib
from openapi_spec_validator import validate
from jsonschema import Draft202012Validator, FormatChecker
r=Path(__file__).resolve().parents[1]
doc=json.loads((r/'contracts/openapi.json').read_text()); validate(doc)
schemas=doc['components']['schemas']
def check(name,value):
 schema={**schemas[name],'components':doc['components']}
 Draft202012Validator(schema,format_checker=FormatChecker()).validate(value)
fixtures=json.loads((r/'contracts/fixtures/schema-examples.json').read_text())
for name,value in fixtures.items():check(name,value)
check('CatalogResponse',json.loads((r/'contracts/fixtures/catalog.json').read_text()))
# Fail closed for security enums, bound identities, confirmation and request field injection.
negative=[]
for key,value in [('accessMode','vip'),('variant','preview'),('byteSize',33554433),('sha256','invalid')]:
 bad=deepcopy(fixtures['OfflinePermit']);bad[key]=value;negative.append(('OfflinePermit',bad))
for name,key,value in [('PlaybackGrant','authMode','unknown'),('DeleteConfirmRequest','confirmedScopeVersion','single-service'),('RefreshRequest','generation',-1),('EntitlementSource','kind','future-access'),('Config','capabilities',{'musicPurchases':True}),('TokenRequest','codeVerifier','short')]:
 bad=deepcopy(fixtures[name]);bad[key]=value;negative.append((name,bad))
bad=deepcopy(fixtures['PlaybackGrant']);bad.update(authMode='session_bearer',accountId=None);negative.append(('PlaybackGrant',bad))
bad=deepcopy(fixtures['DeletePrepared']);bad['accountId']='leaked';negative.append(('DeletePrepared',bad))
bad=deepcopy(fixtures['GrantRequest']);bad['authMode']='public';negative.append(('GrantRequest',bad))
bad=deepcopy(fixtures['PlaybackGrant']);bad['playbackUrl']+='?accessToken=fixture';negative.append(('PlaybackGrant',bad))
bad=deepcopy(fixtures['ListenRequest']);bad.pop('occurredAt');negative.append(('ListenRequest',bad))
bad=deepcopy(fixtures['ListenRequest']);bad['occurredAt']='not-a-date';negative.append(('ListenRequest',bad))
bad=deepcopy(fixtures['ListenRequest']);bad['audibleSeconds']=4.9;negative.append(('ListenRequest',bad))
for name,value in negative:
 try:check(name,value)
 except Exception:pass
 else:raise AssertionError('Accepted invalid '+name)
keys=json.loads((r/'contracts/error-keys.json').read_text()); languages=json.loads((r/'Resources/Localizations.json').read_text())
for lang in ['zh-Hans','zh-Hant','en','ja']:assert all(languages[lang].get(key) for key in keys)
receipt=bytes(range(32));encoded=base64.urlsafe_b64encode(receipt).decode().rstrip('=')
assert len(encoded)==43 and hashlib.sha256(base64.urlsafe_b64decode(encoded+'=')).hexdigest()==fixtures['DeletePrepareRequest']['deletionReceiptHash']
paths=doc['paths'];receiptPath=paths['/api/mobile/v1/deletion-requests/{id}/status']['get']
assert receiptPath['security']==[{'DeletionReceipt':[]}]
for name in ['prepare','{id}/confirm']:
 assert paths['/api/mobile/v1/me/deletion-requests/'+name]['post']['security']==[{'Bearer':[]}]
assert not any('/subscriptions/' in path for path in paths)
assert '/auth/mobile/authorize' in paths
assert sum(len(p) for p in paths.values())==26
print(f'OpenAPI valid: 26 operations, {len(fixtures)+1} positive fixtures, {len(negative)} negative fixtures; four-language error keys and receipt hash verified.')
