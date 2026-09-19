"""M1 proposed v1.0 wire contract. This generates documentation, never server routes."""
from pathlib import Path
import json
r=Path(__file__).resolve().parents[1]
def ref(n): return {'$ref':'#/components/schemas/'+n}
def obj(p,required=None,closed=False): return {'type':'object','properties':p,'required':list(p) if required is None else required,'additionalProperties':not closed}
def arr(x): return {'type':'array','items':x,'maxItems':100}
def enum(*x): return {'type':'string','enum':list(x)}
S={'type':'string','minLength':1,'maxLength':200}; ID={**S,'maxLength':128}; B={'type':'boolean'}; N={'type':'integer','minimum':0}; D={'type':'string','format':'date-time'}; nullableD={'anyOf':[D,{'type':'null'}]}; nullableID={'anyOf':[ID,{'type':'null'}]}
text={'type':'string','maxLength':4000}; secret={'type':'string','minLength':32,'maxLength':4096,'description':'Sensitive value; never log or cache. Response credentials must remain decodable by generated clients.'}; cursor={'anyOf':[S,{'type':'null'}]}
s={}
s['Track']=obj({'id':ID,'title':S,'artist':S,'durationSeconds':{'type':'number','minimum':0,'maximum':86400},'audioVersion':{'type':'integer','minimum':1},'access':enum('free','vip','preview','unavailable')})
s['Track']['properties']['coverUrl']={'anyOf':[{'type':'string','format':'uri'},{'type':'null'}]}
s['Catalog']=obj({'items':arr(ref('Track')),'nextCursor':cursor})
text={'type':'string','maxLength':131072}
s['LyricLine']=obj({'startSeconds':{'type':'number','minimum':0},'text':text})
s['Lyrics']=obj({'kind':enum('none','plain','timed'),'text':text,'lines':arr(ref('LyricLine')),'audioVersion':{'type':'integer','minimum':1}})
s['Lyrics']['properties']['lines']['maxItems']=10000
s['TrackDetail']=obj({'track':ref('Track'),'summary':text,'coverUrl':{'anyOf':[{'type':'string','format':'uri'},{'type':'null'}]},'lyrics':ref('Lyrics'),'genres':arr(S),'moods':arr(S),'previewAvailable':B,'previewSourceStartSeconds':{'anyOf':[{'type':'number','minimum':0},{'type':'null'}]},'previewDurationSeconds':{'anyOf':[{'type':'number','exclusiveMinimum':0},{'type':'null'}]}})
s['Collection']=obj({'id':ID,'slug':S,'title':S,'description':text,'version':{'type':'integer','minimum':1},'tracks':arr(ref('Track')),'nextCursor':cursor})
s['Featured']=obj({'tracks':arr(ref('Track')),'collections':arr(ref('Collection'))})
s['Config']=obj({'apiVersion':{'const':'1'},'minimumAppVersion':S,'capabilities':obj({'musicCatalog':B,'nativeAuthentication':B,'musicPlayback':B,'personalSync':B,'accountDeletion':B,'musicPurchases':{'const':False}}),'storeUrl':{'anyOf':[{'type':'string','format':'uri'},{'type':'null'}]}})
s['Account']=obj({'accountId':ID,'displayName':S,'status':enum('active','restricted','deletion_pending')})
s['EntitlementSource']=obj({'kind':enum('site_vip','music_subscription'),'provider':enum('station','apple'),'status':enum('active','expired','revoked','grace'),'validUntil':D})
s['Entitlements']=obj({'accountId':ID,'music':obj({'canPlayVipFull':B,'accessValidUntil':nullableD,'revalidateAt':D,'sources':arr(ref('EntitlementSource'))}),'siteVip':obj({'active':B,'validUntil':nullableD})})
s['TokenRequest']=obj({'clientId':{'const':'station-cat-ios'},'code':secret,'codeVerifier':{'type':'string','minLength':43,'maxLength':128,'pattern':'^[A-Za-z0-9._~-]+$'},'redirectUri':{'type':'string','format':'uri'}},closed=True)
s['RefreshRequest']=obj({'clientId':{'const':'station-cat-ios'},'refreshToken':secret,'refreshRequestId':ID,'generation':N},closed=True)
tokens={'accountId':ID,'sessionId':ID,'tokenFamilyId':ID,'generation':N,'accessToken':secret,'accessExpiresAt':D,'refreshToken':secret,'refreshExpiresAt':D,'absoluteExpiresAt':D}
s['Tokens']=obj(tokens)
s['RefreshResult']=obj({**tokens,'refreshRequestId':ID,'previousGeneration':N,'replayUntil':D})
s['LogoutRequest']=obj({'refreshToken':secret},closed=True)
s['ReauthRequest']=obj({'password':secret,'totpCode':{'type':'string','maxLength':6}},closed=True)
s['RecentAuthentication']=obj({'validUntil':D})
s['GrantRequest']=obj({'audioVersion':{'type':'integer','minimum':1},'variant':enum('full','preview')},closed=True)
s['PlaybackGrant']=obj({'playbackUrl':{'type':'string','format':'uri','pattern':'^https://[^/?#]+/api/mobile/v1/music/media/[A-Za-z0-9_-]{43}/audio$'},'expiresAt':D,'playbackValidUntil':D,'revalidateAt':D,'authMode':enum('public','session_bearer'),'accountId':nullableID,'sessionId':nullableID,'trackId':ID,'audioVersion':{'type':'integer','minimum':1},'variant':enum('full','preview'),'durationSeconds':{'type':'number','exclusiveMinimum':0},'previewSourceStartSeconds':{'anyOf':[{'type':'number','minimum':0},{'type':'null'}]}})
s['PlaybackGrant']['allOf']=[{'if':{'properties':{'authMode':{'const':'session_bearer'}}},'then':{'properties':{'accountId':ID,'sessionId':ID}},'else':{'properties':{'accountId':{'type':'null'},'sessionId':{'type':'null'}}}}]
s['Favorite']=obj({'trackId':ID,'favorite':B,'version':N,'updatedAt':D})
s['Favorites']=obj({'items':arr(ref('Favorite')),'nextCursor':cursor,'syncVersion':N})
s['FavoriteRequest']=obj({'favorite':B,'mutationId':ID,'expectedVersion':N},closed=True)
s['RecentItem']=obj({'trackId':ID,'lastPlayedAt':D,'positionSeconds':{'type':'number','minimum':0}})
s['Recent']=obj({'items':arr(ref('RecentItem')),'nextCursor':cursor,'historyEpoch':N})
s['Preferences']=obj({'historyEnabled':B,'historyEpoch':N,'version':N})
s['PreferenceRequest']=obj({'historyEnabled':B,'expectedVersion':N,'mutationId':ID},closed=True)
s['ListenRequest']=obj({'trackId':ID,'audioVersion':{'type':'integer','minimum':1},'variant':enum('full','preview'),'eventId':ID,'historyEpoch':N,'audibleSeconds':{'type':'number','minimum':0},'positionSeconds':{'type':'number','minimum':0}},closed=True)
s['ClearHistoryRequest']=obj({'confirmed':{'const':True},'historyEpoch':N,'mutationId':ID},closed=True)
s['Acknowledged']=obj({'accepted':B})
s['DeletePrepareRequest']=obj({'deletionRequestId':ID,'deletionReceiptHash':{'type':'string','pattern':'^[a-f0-9]{64}$','description':'SHA-256 of decoded 32 random bytes, never of base64url text.'},'scopeVersion':{'const':'station-account-v1'}},closed=True)
s['DeleteConfirmRequest']=obj({'confirmedScopeVersion':{'const':'station-account-v1'}},closed=True)
s['DeletePrepared']=obj({'deletionRequestId':ID,'status':{'const':'prepared'},'scopeVersion':{'const':'station-account-v1'},'prepareExpiresAt':D,'receiptExpiresAt':D,'confirmAccepted':{'const':False}})
s['DeleteAccepted']=obj({'deletionRequestId':ID,'status':enum('accepted','processing','retrying','attention_required','completed'),'confirmAccepted':{'const':True},'stage':S,'confirmedAt':D,'completedAt':nullableD,'receiptExpiresAt':D})
s['DeleteExpired']=obj({'deletionRequestId':ID,'status':{'const':'preparation_expired'},'confirmAccepted':{'const':False},'receiptExpiresAt':D})
s['DeleteStatus']={'oneOf':[ref('DeletePrepared'),ref('DeleteAccepted'),ref('DeleteExpired')]}
# Status output is a minimal receipt-scoped projection: prohibit account/financial data.
for name in ['DeletePrepared','DeleteAccepted','DeleteExpired']: s[name]['additionalProperties']=False
codes=['INVALID_REQUEST','AUTH_REQUIRED','SESSION_REVOKED','REFRESH_REAUTH_REQUIRED','REFRESH_CONFLICT','RECENT_AUTH_REQUIRED','TOTP_REQUIRED','VERSION_CONFLICT','HISTORY_EPOCH_STALE','MUSIC_DISABLED','MEDIA_UNAVAILABLE','GRANT_EXPIRED','ACCESS_DENIED','DELETION_STATUS_UNAVAILABLE','RATE_LIMITED','SERVICE_UNAVAILABLE','CLIENT_UPGRADE_REQUIRED']
s['Error']=obj({'error':obj({'code':enum(*codes),'retryable':B,'retryAfterSeconds':N,'messageKey':enum(*['error.'+c.lower() for c in codes])},required=['code','retryable','messageKey']),'requestId':ID,'serverNow':D})
for name in list(s):
 if not (name.endswith('Request') or name=='Error'):
  s[name+'Response']=obj({'data':ref(name),'requestId':ID,'serverNow':D})
paths={}; prefix='/api/mobile/v1'
def parameter(name,where,schema,required=False): return {'name':name,'in':where,'required':required,'schema':schema}
def endpoint(method,path,response,request=None,auth='Bearer',status='200',description=''):
 full=prefix+path
 security=[] if auth=='none' else ([{}, {'Bearer':[]}] if auth=='optional' else [{auth:[]}])
 pars=[parameter(x[1:-1],'path',ID,True) for x in path.split('/') if x.startswith('{')]
 if path in ['/music/catalog','/me/music/favorites','/me/music/recent']:
  pars += [parameter('limit','query',{'type':'integer','minimum':1,'maximum':100,'default':50}),parameter('cursor','query',S)]
 if path.startswith('/music/') and method=='get' and '/media/' not in path: pars += [parameter('locale','query',enum('en','zh-Hans','zh-Hant','ja'))]
 if path=='/music/collections/{slug}': pars += [parameter('limit','query',{'type':'integer','minimum':1,'maximum':100}),parameter('cursor','query',S)]
 if path=='/music/catalog': pars += [parameter('q','query',{'type':'string','maxLength':200}),parameter('access','query',enum('all','free','vip'))]
 if method in ['post'] and ('deletion-requests' in path and auth=='Bearer'): pars += [parameter('Idempotency-Key','header',ID,True)]
 responses={status:{'description':'Proposed v1.0 response; M1 serves fixtures only.','headers':{'Cache-Control':{'schema':{'type':'string'},'description':'private, no-store for identity, credentials, grants and deletion.'}},'content':{'application/json':{'schema':ref(response+'Response')}}},'default':{'description':'Stable error; 503 never means expired entitlement. No redirects.','content':{'application/json':{'schema':ref('Error')}}}}
 item={'operationId':method+'_'+path.replace('/','_').replace('{','').replace('}','').replace('-','_'),'security':security,'description':description or 'Planned API. Not implemented or deployed by M1.','parameters':pars,'responses':responses,'x-milestone':'v1.0'}
 if request: item['requestBody']={'required':True,'content':{'application/json':{'schema':ref(request)}}}
 paths.setdefault(full,{})[method]=item
endpoint('get','/config','Config',auth='none')
endpoint('post','/auth/token','Tokens','TokenRequest','none',description='Exact registered redirect; S256 PKCE; atomically consume authorization code within 90 seconds. No Cookie fallback.')
endpoint('post','/auth/refresh','RefreshResult','RefreshRequest','none',description='No Cookie or automatic 401 interceptor. Fixed request ID and canonical body across restarts. Original result retained 120 seconds; spent operation tombstone outlives result; outside window require reauthentication, never mint a replacement family.')
endpoint('post','/auth/logout','Acknowledged','LogoutRequest','optional',description='Revoke only. Either Bearer without a body, or no Authorization header plus a refreshToken body. A known current/spent refresh token revokes only its own family; it cannot authenticate, read account data or create tokens. Unknown refresh proof returns the same acknowledgement. This closes logout versus rotation races.')
paths[prefix+'/auth/logout']['post']['requestBody']['required']=False
endpoint('post','/auth/reauth','RecentAuthentication','ReauthRequest',description='M2 isolated implementation: verify existing password and enabled TOTP for this Bearer account; proof bound to session/security version, valid at most five minutes.')
endpoint('get','/me','Account');endpoint('get','/me/entitlements','Entitlements')
endpoint('get','/music/catalog','Catalog',auth='none');endpoint('get','/music/featured','Featured',auth='none')
endpoint('get','/music/tracks/{id}','TrackDetail',auth='none');endpoint('get','/music/collections/{slug}','Collection',auth='none')
endpoint('post','/music/tracks/{id}/playback-grants','PlaybackGrant','GrantRequest','optional',description='Server chooses authMode. VIP full requires Bearer. Account, session, version, variant and expiry are bound. Invalid Bearer never downgrades to public.')
for method in ['get','head']:
 endpoint(method,'/music/media/{grant}/audio','Acknowledged',auth='optional',description='Actual GET/HEAD and every Range re-check grant and requester. session_bearer requires same account/session Bearer. public restricted to valid free/preview. Never redirect or use shared CDN cache. Failure to resolve authorization is 503 without audio.')
 op=paths[prefix+'/music/media/{grant}/audio'][method];op['parameters'].append(parameter('Range','header',{'type':'string','pattern':'^bytes=[0-9]*-[0-9]*$'}))
 op['responses'].pop('200')
 for status in ['200','206']: op['responses'][status]={'description':'Audio body for GET, empty for HEAD. Protected responses private, no-store.','headers':{h:{'schema':{'type':'string'}} for h in ['Content-Length','Content-Type','Content-Range','Accept-Ranges','Cache-Control']},**({'content':{'audio/mpeg':{'schema':{'type':'string','format':'binary'}}}} if method=='get' else {})}
 op['responses']['416']={'description':'Range not satisfiable; no audio.'}
endpoint('get','/me/music/favorites','Favorites');endpoint('put','/me/music/favorites/{id}','Favorite','FavoriteRequest')
endpoint('get','/me/music/recent','Recent');endpoint('delete','/me/music/recent','Preferences','ClearHistoryRequest')
endpoint('get','/me/music/preferences','Preferences');endpoint('patch','/me/music/preferences','Preferences','PreferenceRequest')
endpoint('post','/me/music/listens','Acknowledged','ListenRequest')
endpoint('post','/me/deletion-requests/prepare','DeletePrepared','DeletePrepareRequest',description='Bearer + recent auth <=5 minutes, existing TOTP rules. Idempotency-Key is persisted prepareRequestId. Only prepare; no session revocation or deletion outbox. 10-minute preparation; 14-day receipt. Known placeholder hashes rejected.')
endpoint('post','/me/deletion-requests/{id}/confirm','DeleteAccepted','DeleteConfirmRequest',status='202',description='Explicit consent, Bearer + recent auth + TOTP, persisted confirmRequestId. Atomically accept task, block account, revoke sessions/grants and insert outbox. Receipt alone never authorizes confirmation.')
endpoint('get','/deletion-requests/{id}/status','DeleteStatus',auth='DeletionReceipt',description='Query only; no Bearer, Cookie, refresh interceptor or login redirect. Authorization: DeletionReceipt <unpadded base64url of 32 random bytes>. Strongly consistent minimal status. Invalid/expired/wrong receipt always 404 DELETION_STATUS_UNAVAILABLE.')
paths[prefix+'/deletion-requests/{id}/status']['get']['responses']['404']={'description':'Indistinguishable absent, invalid or expired receipt.','content':{'application/json':{'schema':ref('Error')}}}
paths['/auth/mobile/authorize']={'get':{'operationId':'browser_authorize','security':[],'description':'ASWebAuthenticationSession browser login, including existing TOTP. Exact registered redirect; no arbitrary return URL. Reuse interactive web identity, never website Cookie as native API fallback.','parameters':[parameter(k,'query',v,True) for k,v in {'client_id':{'const':'station-cat-ios'},'redirect_uri':{'type':'string','format':'uri'},'state':{'type':'string','minLength':32},'code_challenge':{'type':'string','pattern':'^[A-Za-z0-9_-]{43}$'},'code_challenge_method':{'const':'S256'}}.items()],'responses':{'200':{'description':'Interactive authentication page','content':{'text/html':{'schema':{'type':'string'}}}},'302':{'description':'Only registered redirect containing code and unchanged state; no tokens in URL.'},'400':{'description':'Invalid request; no redirect.'}}}}
for path, methods in paths.items():
 if '/me/music/' in path:
  for method, operation in methods.items():
   operation['description']='M5 isolated opt-in only. Native Bearer, account isolation. Writes use durable operation IDs and version/epoch checks; conflict requires refresh, never silent overwrite. Favorites max5000 active. History max1000/90days; at least5 audible seconds, not entitlement or reward evidence. Cursor contains snapshot revision and expires on mutation.'
   operation['responses']['200']['description']='Isolated native library result; no production activation.'
doc={'openapi':'3.1.0','info':{'title':'Station Cat Music Native — proposed v1.0 contract','version':'0.5.0','description':'M2 authentication/deletion requests and M3 catalog/playback are implemented only in isolated local development; M5 personal sync is implemented only behind a separate isolated opt-in; physical deletion execution remains proposed. Default application is Mock with networking disabled. UTF-8 JSON; ISO8601 UTC timestamps; positions/durations seconds. Unknown capabilities and authorization modes fail closed. Personal pagination default50/max100. No StoreKit v1.1 paths in this contract.'},'servers':[{'url':'https://mock.invalid','description':'Reserved non-routable placeholder; configure approved isolated service in M2.'}],'paths':paths,'components':{'securitySchemes':{'Bearer':{'type':'http','scheme':'bearer','description':'Native access token only. Do not accept website Cookie as fallback.'},'DeletionReceipt':{'type':'apiKey','in':'header','name':'Authorization','description':'DeletionReceipt followed by unpadded base64url of exactly32 random bytes; query-only credential, never Bearer.'}},'schemas':s}}
(r/'contracts/openapi.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n')
# A deterministic, explicitly fictional positive fixture for every named schema.
def sample(schema):
 if '$ref' in schema:return sample(s[schema['$ref'].split('/')[-1]])
 if 'const' in schema:return schema['const']
 if 'enum' in schema:return schema['enum'][0]
 if 'oneOf' in schema:return sample(schema['oneOf'][0])
 if 'anyOf' in schema:return sample(schema['anyOf'][0])
 t=schema.get('type')
 if t=='object':
  value={k:sample(v) for k,v in schema['properties'].items() if k in schema['required']}
  if value.get('authMode')=='public': value.update(accountId=None,sessionId=None)
  if 'playbackUrl' in value and value.get('variant')=='full': value['previewSourceStartSeconds']=None
  for k in ['expiresAt','playbackValidUntil','accessValidUntil','accessExpiresAt','refreshExpiresAt','absoluteExpiresAt','receiptExpiresAt','prepareExpiresAt','replayUntil']:
   if k in value: value[k]='2026-09-16T00:10:00Z'
  if 'revalidateAt' in value:value['revalidateAt']='2026-09-16T00:01:00Z'
  return value
 if t=='array':return []
 if t=='boolean':return False
 if t in ['integer','number']:return schema.get('minimum',schema.get('exclusiveMinimum',-1)+1)
 if t=='null':return None
 if schema.get('format')=='date-time':return '2026-09-16T00:00:00Z'
 if schema.get('pattern','').startswith('^https:'):return 'https://mock.invalid/api/mobile/v1/music/media/'+'f'*43+'/audio'
 if schema.get('format')=='uri':return 'https://mock.invalid/FIXTURE_ONLY'
 if schema.get('pattern')=='^[a-f0-9]{64}$':return '630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd'
 if schema.get('minLength',0)>20:return 'FIXTUREONLY' * 5
 return 'fixture-only'[:schema.get('maxLength',12)]
(r/'contracts/fixtures/schema-examples.json').write_text(json.dumps({n:sample(v) for n,v in s.items()},ensure_ascii=False,indent=2)+'\n')
(r/'contracts/error-keys.json').write_text(json.dumps(['error.'+c.lower() for c in codes],indent=2)+'\n')
print('Generated',sum(len(p) for p in paths.values()),'operations and',len(s),'schemas')
