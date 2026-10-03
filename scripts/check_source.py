"""Small deterministic guard, complementary to review; not a security certification."""
from pathlib import Path
import re,json
root=Path(__file__).resolve().parents[1]
files=[p for d in ['Core','StationCatMusic','Tests','TestsSupport','IntegrationProbes','UITests','Config','contracts','scripts','.github'] for p in (root/d).rglob('*') if p.is_file() and p.suffix not in ['.pyc']]
patterns=[r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',r'gh[pousr]_[A-Za-z0-9]{30,}',r'AKIA[0-9A-Z]{16}']
for p in files:
 text=p.read_text()
 # Do not scan the scanner's literal regex definitions as credentials.
 if p.name!='check_source.py':assert not any(re.search(pattern,text) for pattern in patterns),f'Potential credential: {p}'
 if p.suffix=='.swift' and p.parent.name in ['Core','StationCatMusic']:
  assert 'http://' not in text and 'NSAllowsArbitraryLoads' not in text,p
  if p.name == 'NativeRuntimeConfiguration.swift':
   assert text.count('wwwstationcat.org') == 1 and 'static let origin = "https://wwwstationcat.org"' in text,p
  else:assert 'wwwstationcat.org' not in text,p
source='\n'.join(p.read_text() for p in (root/'Core').glob('*.swift'))
assert source.count('AVPlayer()')==1
assert 'case mock, development, staging, production' in source
assert 'guard environment == .mock else' in source
assert 'guard configuration.accountDeletionAllowed else' in source
profile=json.loads((root/'Config/ProductionActivation.example.json').read_text())
assert profile['enabled'] is False and not any(profile['capabilities'].values())
for name in ['Mock','Development','Staging','Production']:
 config=(root/'Config'/(name+'.xcconfig')).read_text()
 for key in ['STATION_NATIVE_AUTH_ENABLED','STATION_NATIVE_MUSIC_ENABLED','STATION_PERSONAL_SYNC_ENABLED','STATION_PRODUCTION_ACTIVATION_ENABLED']:
  assert re.search(r'^'+key+r' = NO$',config,re.M), (name,key)
 for key in ['STATION_NATIVE_AUTH_ORIGIN','STATION_MUSIC_WEB_ORIGIN','STATION_PRODUCTION_ACTIVATION_PROFILE']:
  assert re.search(r'^'+key+r' =\s*$',config,re.M), (name,key)
assert 'R2.local' not in (root/'Config/Production.xcconfig').read_text()
assert 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' in source
assert 'kSecAttrSynchronizable as String: false' in source
locales=json.loads((root/'Resources/Localizations.json').read_text())
assert all(set(d)==set(locales['en']) for d in locales.values())
print('Source guards passed: no recognizable embedded credentials/HTTP exceptions; one player owner; Mock networking boundary; Keychain storage policy; four locale parity.')
