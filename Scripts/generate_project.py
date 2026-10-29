"""Generate a dependency-free Xcode project; works on Windows and macOS."""
from pathlib import Path
import hashlib, json, plistlib
ROOT = Path(__file__).resolve().parents[1]

def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def quoted(value): return json.dumps(str(value), ensure_ascii=False)
def value(v):
    if isinstance(v, dict): return '{ ' + ' '.join(f'{k} = {value(x)};' for k, x in v.items()) + ' }'
    if isinstance(v, list): return '(' + ', '.join(value(x) for x in v) + ')'
    return quoted(v)

def generate():
    objs = {}
    def obj(key, isa, **fields):
        uid = ident(key); objs[uid] = {'isa': isa, **fields}; return uid
    files = sorted((ROOT / 'Sources').glob('*.swift'))
    source_refs, builds = [], []
    for p in files:
        ref = obj('file:' + p.name, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path='Sources/' + p.name, sourceTree='<group>')
        source_refs.append(ref); builds.append(obj('build:' + p.name, 'PBXBuildFile', fileRef=ref))
    asset = obj('assets', 'PBXFileReference', lastKnownFileType='folder.assetcatalog', path='Resources/Assets.xcassets', sourceTree='<group>')
    asset_build = obj('assetbuild', 'PBXBuildFile', fileRef=asset)
    privacy = obj('privacy', 'PBXFileReference', lastKnownFileType='text.xml', path='Resources/PrivacyInfo.xcprivacy', sourceTree='<group>')
    privacy_build = obj('privacybuild', 'PBXBuildFile', fileRef=privacy)
    product = obj('product', 'PBXFileReference', explicitFileType='wrapper.application', includeInIndex='0', path='Hearth.app', sourceTree='BUILT_PRODUCTS_DIR')
    products = obj('products', 'PBXGroup', children=[product], name='Products', sourceTree='<group>')
    main = obj('main', 'PBXGroup', children=source_refs+[asset, privacy, products], sourceTree='<group>')
    sources = obj('sources', 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=builds, runOnlyForDeploymentPostprocessing='0')
    resources = obj('resources', 'PBXResourcesBuildPhase', buildActionMask='2147483647', files=[asset_build, privacy_build], runOnlyForDeploymentPostprocessing='0')
    frameworks = obj('frameworks', 'PBXFrameworksBuildPhase', buildActionMask='2147483647', files=[], runOnlyForDeploymentPostprocessing='0')
    project_configs, app_configs = [], []
    for mode in ('Debug','Release'):
        project_configs.append(obj('project:'+mode, 'XCBuildConfiguration', name=mode, buildSettings={'CLANG_ENABLE_MODULES':'YES','SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym','ENABLE_TESTABILITY':'YES' if mode=='Debug' else 'NO'}))
        app_configs.append(obj('app:'+mode,'XCBuildConfiguration',name=mode,buildSettings={'PRODUCT_NAME':'Hearth','PRODUCT_BUNDLE_IDENTIFIER':'app.hearth.familyledger','INFOPLIST_FILE':'Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO','TARGETED_DEVICE_FAMILY':'1,2','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_STYLE':'Automatic','MARKETING_VERSION':'1.0','CURRENT_PROJECT_VERSION':'1','ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],'SWIFT_EMIT_LOC_STRINGS':'YES','SWIFT_STRICT_CONCURRENCY':'minimal'}))
    pc = obj('projectconfig','XCConfigurationList',buildConfigurations=project_configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
    ac = obj('appconfig','XCConfigurationList',buildConfigurations=app_configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
    target = obj('target','PBXNativeTarget',buildConfigurationList=ac,buildPhases=[sources,frameworks,resources],buildRules=[],dependencies=[],name='Hearth',productName='Hearth',productReference=product,productType='com.apple.product-type.application')
    project = obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600'},buildConfigurationList=pc,compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',knownRegions=['en','zh-Hans','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target])
    folder = ROOT/'Hearth.xcodeproj'; folder.mkdir(exist_ok=True)
    lines=['// !$*UTF8*$!','{','archiveVersion = 1;','classes = {};','objectVersion = 56;','objects = {']
    lines += [f'{uid} = {value(fields)};' for uid,fields in objs.items()]
    lines += ['};',f'rootObject = {quoted(project)};','}']
    (folder/'project.pbxproj').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    schemes=folder/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
    (schemes/'Hearth.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Hearth.app" BlueprintName="Hearth" ReferencedContainer="container:Hearth.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Hearth.app" BlueprintName="Hearth" ReferencedContainer="container:Hearth.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''',encoding='utf-8')
    print('Generated Hearth.xcodeproj ('+str(len(files))+' Swift files)')
if __name__=='__main__': generate()
