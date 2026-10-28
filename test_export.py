"""Exercise the real app exporter; no third-party Python packages required.

Usage: python3 VideoSaverMaker-source/test_export.py Sky.mp4
Playback and AppKit UI checks require a desktop session and are separate.
"""
import hashlib
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
app = root / 'Video Saver Maker.app'
binary = app / 'Contents/MacOS/VideoSaverMaker'
video = pathlib.Path(sys.argv[1]).resolve()


def invoke(folder, name, videos, *options, success=True):
    run = subprocess.run([str(binary), '--export', '--name', name,
                          '--output', str(folder), *options,
                          *map(str, videos)], capture_output=True, text=True)
    assert (run.returncode == 0) == success, (run.stdout, run.stderr)
    return folder / (name.removesuffix('.saver') + '.saver')


def read_plist(path):
    with path.open('rb') as stream:
        return plistlib.load(stream)


def check_signature(path):
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(path)], check=True)


with tempfile.TemporaryDirectory(prefix='vsm-check-') as temp:
    folder = pathlib.Path(temp)
    check_signature(app)
    single = invoke(folder, '單一影片 Sky', [video])
    check_signature(single)
    info = read_plist(single / 'Contents/Info.plist')
    playlist = read_plist(single / 'Contents/Resources/Playlist.plist')
    assert info['CFBundleName'] == '單一影片 Sky'
    assert playlist == {'files': ['Video-0001.mp4'], 'fit': 'fill', 'shuffle': False}
    original_hash = hashlib.sha256(video.read_bytes()).digest()
    assert hashlib.sha256((single / 'Contents/Resources/Video-0001.mp4').read_bytes()).digest() == original_hash
    print('PASS: single-video export, Unicode name, embedded video integrity, signature')

    # Equal basenames in separate folders must never overwrite one another.
    alternate = folder / 'input with spaces' / video.name
    alternate.parent.mkdir()
    shutil.copyfile(video, alternate)
    multiple = invoke(folder, 'Playlist $(literal).saver', [video, alternate], '--shuffle', '--fit')
    check_signature(multiple)
    multi_info = read_plist(multiple / 'Contents/Info.plist')
    multi_list = read_plist(multiple / 'Contents/Resources/Playlist.plist')
    assert multi_list == {'files': ['Video-0001.mp4', 'Video-0002.mp4'], 'fit': 'fit', 'shuffle': True}
    for filename in multi_list['files']:
        assert hashlib.sha256((multiple / 'Contents/Resources' / filename).read_bytes()).digest() == original_hash
    assert info['NSPrincipalClass'] != multi_info['NSPrincipalClass']
    print('PASS: playlist, duplicate basenames, spaces, literal shell characters, fit/shuffle')

    # Two exports of the same name retain a stable bundle and class identity.
    other = folder / 'other'
    other.mkdir()
    rebuilt = invoke(other, '單一影片 Sky', [video])
    rebuilt_info = read_plist(rebuilt / 'Contents/Info.plist')
    assert rebuilt_info['CFBundleIdentifier'] == info['CFBundleIdentifier']
    assert rebuilt_info['NSPrincipalClass'] == info['NSPrincipalClass']
    before = (single / 'Contents/Info.plist').read_bytes()
    invoke(folder, '單一影片 Sky', [video], success=False)
    assert before == (single / 'Contents/Info.plist').read_bytes()
    for bad in ['', '../escape', '.hidden', 'bad:name']:
        invoke(folder, bad, [video], success=False)
    invoke(folder, 'No Videos', [], success=False)
    invoke(folder, 'Missing', [folder / 'missing.mp4'], success=False)
    fake = folder / 'fake.mp4'
    fake.write_bytes(b'This is not a video.')
    invoke(folder, 'Fake', [fake], success=False)
    invoke(folder / 'missing directory', 'Cannot Write', [video], success=False)
    assert not list(folder.rglob('.vsm-*'))
    print('PASS: stable identity, no overwrite, invalid names/files, I/O failure, cleanup')

    # Load both exported bundles into one process: each must resolve its own engine.
    harness = folder / 'load.m'
    harness.write_text('''
#import <ScreenSaver/ScreenSaver.h>
int main(int argc, const char *argv[]) {
 @autoreleasepool {
  Class previous = Nil;
  for (int i = 1; i < argc; i++) {
   NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[i]]];
   NSError *error = nil;
   if (![bundle loadAndReturnError:&error]) { NSLog(@"%@",error); return 1; }
   Class cls = bundle.principalClass;
   if (!cls || cls == previous || ![cls isSubclassOfClass:ScreenSaverView.class]) return 2;
   if (![[NSBundle bundleForClass:cls].bundlePath isEqual:bundle.bundlePath]) return 3;
   previous = cls;
  }
 }
 return 0;
}
''')
    helper = folder / 'load'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'ScreenSaver',
                    '-framework', 'AppKit', str(harness), '-o', str(helper)], check=True)
    subprocess.run([str(helper), str(single), str(multiple)], check=True)
    print('PASS: two different screensavers load in one process with independent resource bundles')

print('All exporter checks passed. Desktop playback and drag-and-drop remain manual checks.')
