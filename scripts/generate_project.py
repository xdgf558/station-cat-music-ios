"""Dependency-free, deterministic Xcode project generator. Run after adding source files."""
from pathlib import Path
import hashlib,json,plistlib
root=Path(__file__).resolve().parents[1]
project=root/'StationCatMusic.xcodeproj';project.mkdir(exist_ok=True)
objects={}
def ident(s):return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def obj(key,isa,**values):
 i=ident(key);objects[i]={'isa':isa,**values};return i
def quote(s):return json.dumps(s,ensure_ascii=False)
def fmt(v,depth=0):
 pad='\t'*depth;inner='\t'*(depth+1)
 if isinstance(v,dict):return '{\n'+ '\n'.join(inner+quote(k)+' = '+fmt(x,depth+1)+';' for k,x in v.items())+'\n'+pad+'}'
 if isinstance(v,list):return '(\n'+',\n'.join(inner+fmt(x,depth+1) for x in v)+'\n'+pad+')'
 return quote(str(v))

files=[]
def ref(path,kind):
 i=obj('file:'+path,'PBXFileReference',lastKnownFileType=kind,path=path,sourceTree='<group>');files.append(i);return i
sources=[ref(str(p.relative_to(root)),'sourcecode.swift') for d in ['Core','StationCatMusic'] for p in sorted((root/d).glob('*.swift'))]
tests=[ref(str(p.relative_to(root)),'sourcecode.swift') for directory in ['Tests','TestsSupport'] for p in sorted((root/directory).glob('*.swift'))]
uits=[ref(str(p.relative_to(root)),'sourcecode.swift') for p in sorted((root/'UITests').glob('*.swift'))]
resources=[ref('Resources/Localizations.json','text.json'),ref('contracts/fixtures/catalog.json','text.json'),ref('contracts/fixtures/schema-examples.json','text.json')]
configs=['Mock','Development','Staging','Production']
configrefs={n:ref('Config/'+n+'.xcconfig','text.xcconfig') for n in configs}
products=[];targets=[]
def configlist(label,values):
 items=[]
 for n in configs:
  settings=dict(values)
  if label in ['StationCatMusic','StationCatMusicTests','StationCatMusicUITests'] and n in ['Staging','Production']:
   suffix='' if label=='StationCatMusic' else ('.uitests' if label.endswith('UITests') else '.tests')
   settings['PRODUCT_BUNDLE_IDENTIFIER']='org.stationcat.music'+('.staging' if n=='Staging' else '')+suffix
   settings['DEVELOPMENT_TEAM']='2AM5S7BM2N'
   if label=='StationCatMusic' and n=='Staging':settings['CODE_SIGN_ENTITLEMENTS']='$(STATION_APP_ENTITLEMENTS)'
  items.append(obj(label+n,'XCBuildConfiguration',name=n,baseConfigurationReference=configrefs[n],buildSettings=settings))
 return obj(label+'configs','XCConfigurationList',buildConfigurations=items,defaultConfigurationIsVisible=0,defaultConfigurationName='Mock')
def phase(label,kind,refs):
 return obj(label,kind,buildActionMask=2147483647,files=[obj(label+f,'PBXBuildFile',fileRef=f) for f in refs],runOnlyForDeploymentPostprocessing=0)
appID=ident('target:StationCatMusic')
for name,refs,productType in [('StationCatMusic',sources,'com.apple.product-type.application'),('StationCatMusicTests',tests,'com.apple.product-type.bundle.unit-test'),('StationCatMusicUITests',uits,'com.apple.product-type.bundle.ui-testing')]:
 isapp=name=='StationCatMusic';isui=name.endswith('UITests')
 product=obj(name+'product','PBXFileReference',explicitFileType='wrapper.application' if isapp else 'wrapper.cfbundle',path=name+('.app' if isapp else '.xctest'),sourceTree='BUILT_PRODUCTS_DIR');products.append(product)
 settings={'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':'org.stationcat.music.dev'+('' if isapp else ('.uitests' if isui else '.tests')),'GENERATE_INFOPLIST_FILE':'YES','SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','SWIFT_DEFAULT_ACTOR_ISOLATION':'nonisolated','ENABLE_TESTABILITY':'YES','CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1','IPHONEOS_DEPLOYMENT_TARGET':'18.0','SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @loader_path/Frameworks'}
 if isapp:settings.update({'GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'Config/Info.plist','INFOPLIST_KEY_CFBundleDisplayName':'Station Cat Music','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_StationEnvironment':'$(STATION_ENVIRONMENT)','INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait','INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.music','MARKETING_VERSION':'0.1.0','CURRENT_PROJECT_VERSION':'1'})
 elif isui:settings['TEST_TARGET_NAME']='StationCatMusic'
 else:settings.update({'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/StationCatMusic.app/StationCatMusic','BUNDLE_LOADER':'$(TEST_HOST)'})
 dependencies=[]
 if not isapp:
  proxy=obj(name+'proxy','PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=appID,remoteInfo='StationCatMusic')
  dependencies=[obj(name+'dep','PBXTargetDependency',target=appID,targetProxy=proxy)]
 target=obj('target:'+name,'PBXNativeTarget',name=name,productName=name,productReference=product,productType=productType,buildConfigurationList=configlist(name,settings),buildPhases=[phase(name+'src','PBXSourcesBuildPhase',refs),phase(name+'frameworks','PBXFrameworksBuildPhase',[]),phase(name+'resources','PBXResourcesBuildPhase',resources if isapp else [])],buildRules=[],dependencies=dependencies);targets.append(target)
prodgroup=obj('products','PBXGroup',name='Products',children=products,sourceTree='<group>')
group=obj('group','PBXGroup',children=files+[prodgroup],sourceTree='<group>')
obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2640'},buildConfigurationList=configlist('project',{'CLANG_ENABLE_MODULES':'YES','SWIFT_OPTIMIZATION_LEVEL':'-Onone','DEBUG_INFORMATION_FORMAT':'dwarf','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}),compatibilityVersion='Xcode 14.0',developmentRegion='en',knownRegions=['en','zh-Hans','zh-Hant','ja','Base'],mainGroup=group,productRefGroup=prodgroup,projectDirPath='',projectRoot='',targets=targets)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+fmt({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':ident('project')})+'\n')
scheme=project/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
def reference(name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target:"+name)}" BuildableName="{name}{".app" if name=="StationCatMusic" else ".xctest"}" BlueprintName="{name}" ReferencedContainer="container:StationCatMusic.xcodeproj" />'
(scheme/'StationCatMusic.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2640" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference('StationCatMusic')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Mock" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO">{reference('StationCatMusicTests')}</TestableReference><TestableReference skipped="NO">{reference('StationCatMusicUITests')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Mock" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{reference('StationCatMusic')}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Production"/><AnalyzeAction buildConfiguration="Mock"/><ArchiveAction buildConfiguration="Production" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated project with',len(sources),'app sources,',len(tests),'test sources')
staging=(scheme/'StationCatMusic.xcscheme').read_text().replace('buildConfiguration="Mock"','buildConfiguration="Staging"').replace('buildConfiguration="Production"','buildConfiguration="Staging"')
(scheme/'StationCatMusicStaging.xcscheme').write_text(staging)
