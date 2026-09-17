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
  assert 'wwwstationcat.org' not in text,p
source='\n'.join(p.read_text() for p in (root/'Core').glob('*.swift'))
assert source.count('AVPlayer()')==1
assert 'case mock, development, staging, production' in source
assert 'guard environment == .mock else' in source
assert 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' in source
assert 'kSecAttrSynchronizable as String: false' in source
locales=json.loads((root/'Resources/Localizations.json').read_text())
assert all(set(d)==set(locales['en']) for d in locales.values())
print('Source guards passed: no recognizable embedded credentials/HTTP exceptions; one player owner; Mock networking boundary; Keychain storage policy; four locale parity.')
