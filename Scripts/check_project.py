"""Static project/package checks; not a replacement for Xcode compilation."""
from pathlib import Path
import hashlib,json,plistlib,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Scripts'))
from generate_project import generate,ident

def check():
    generate()
    pbx=(ROOT/'Hearth.xcodeproj/project.pbxproj').read_text()
    definitions=set(re.findall(r'^([A-F0-9]{24}) = ',pbx,re.M))
    refs=set(re.findall(r'"([A-F0-9]{24})"',pbx))
    assert refs <= definitions, 'undefined project reference'
    for p in (ROOT/'Sources').glob('*.swift'): assert 'Sources/'+p.name in pbx,p
    info=plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())
    assert info['NSFaceIDUsageDescription'] and info['CFBundleIdentifier']=='$(PRODUCT_BUNDLE_IDENTIFIER)'
    privacy=plistlib.loads((ROOT/'Resources/PrivacyInfo.xcprivacy').read_bytes())
    assert privacy['NSPrivacyTracking'] is False
    assert not list(ROOT.rglob('*.p12')) and not list(ROOT.rglob('*.mobileprovision'))
    for p in (ROOT/'Resources/Assets.xcassets').rglob('Contents.json'):json.loads(p.read_text())
    import xml.etree.ElementTree as ET
    ET.parse(ROOT/'Hearth.xcodeproj/xcshareddata/xcschemes/Hearth.xcscheme')
    print(f'Static project checks passed: {len(definitions)} objects, valid plist/assets/scheme. Xcode compilation still required.')
if __name__=='__main__':check()
