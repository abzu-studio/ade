#!/usr/bin/env python3
"""Build an audited DMG, with explicit unsigned-preview or notarized distribution modes."""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ENV = dict(os.environ)
ENV.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
ENTITLEMENTS = {
    'com.apple.security.app-sandbox': True,
    'com.apple.security.files.user-selected.read-write': True,
}


def run(*args):
    return subprocess.check_output([str(a) for a in args], env=ENV, cwd=ROOT)


def verify(app, developer_id=False):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.ade.mac':
        raise ValueError('Unexpected bundle identifier')
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    architectures = set(run('xcrun', 'lipo', '-archs', executable).decode().split())
    if architectures != {'arm64', 'x86_64'}:
        raise ValueError('Both arm64 and x86_64 are required')
    run('codesign', '--verify', '--deep', '--strict', app)
    entitlements = plistlib.loads(run('codesign', '-d', '--entitlements', '-', '--xml', app))
    if entitlements != ENTITLEMENTS:
        raise ValueError('Unexpected entitlements: distribution must not allow debugging or networking')
    signature = subprocess.run(
        ['codesign', '-dvv', str(app)], capture_output=True, check=True, env=ENV).stderr.decode()
    if 'runtime)' not in signature and ',runtime,' not in signature:
        raise ValueError('Hardened runtime is required')
    if developer_id and 'Authority=Developer ID Application:' not in signature:
        raise ValueError('Developer ID Application signing is required')
    strings = run('strings', executable)
    forbidden = [b'ADE_UI_TEST_RUN', b'load-demo', b'DemoData', b'Espacio de ejemplo',
                 b'Persona 01', b'/' + b'Users/']
    if any(value in strings for value in forbidden):
        raise ValueError('Development fixtures or local build paths found in executable')
    for path in app.rglob('*'):
        if (path.name.startswith(('workspace', '.env'))
                or path.suffix in {'.log', '.p12', '.p8', '.key', '.xcuserstate'}
                or path.name in {'xcuserdata', '.DS_Store'}):
            raise ValueError('Private or development artifact in application: ' + path.name)
    dependencies = run('xcrun', 'otool', '-L', executable).decode().splitlines()
    for line in dependencies:
        if line.startswith('\t'):
            library = line.strip().split(' (', 1)[0]
            if not library.startswith(('/System/Library/', '/usr/lib/')):
                raise ValueError('Unexpected external dependency: ' + library)
    for license_name in ('barlowcondensed-OFL.txt', 'ibmplexmono-OFL.txt', 'inter-OFL.txt'):
        if not (app / 'Contents/Resources/Resources/Fonts' / license_name).is_file():
            raise ValueError('Missing bundled font license: ' + license_name)
    return info


def notarize(artifact, profile, directory, label):
    # Credentials are read from Keychain; never accept passwords in arguments.
    result = subprocess.run(
        ['xcrun', 'notarytool', 'submit', str(artifact), '--keychain-profile', profile,
         '--wait', '--timeout', '30m', '--output-format', 'json'],
        env=ENV, cwd=ROOT, capture_output=True)
    (directory / (label + '-notary.json')).write_bytes(result.stdout)
    (directory / (label + '-notary.log')).write_bytes(result.stderr)
    result.check_returncode()
    status = json.loads(result.stdout)
    if status.get('status') != 'Accepted':
        raise ValueError('Apple did not accept the submission; see the local notarization report')


def package(args):
    signed = args.command == 'distribute'
    if signed:
        identities = run('security', 'find-identity', '-v', '-p', 'codesigning').decode()
        matches = re.findall(r'([A-Fa-f0-9]{40}) "(Developer ID Application:[^"]+)"', identities)
        if not any(args.identity in (sha, name) for sha, name in matches):
            raise ValueError('A valid Developer ID Application certificate with its private key is required')
    preview = args.command == 'preview'
    output = ROOT / 'dist' / ('release' if signed else 'preview' if preview else 'local')
    output.mkdir(parents=True, exist_ok=True)
    # Each attempt remains isolated, including incomplete notarization submissions.
    attempt = pathlib.Path(tempfile.mkdtemp(prefix='package-', dir=ROOT / 'build'))
    derived = attempt / 'DerivedData'
    print('Building universal Release…', flush=True)
    with (attempt / 'build.log').open('wb') as log:
        subprocess.run([
            'xcodebuild', '-project', 'macos/Ade.xcodeproj', '-scheme', 'Ade',
            '-configuration', 'Release', '-derivedDataPath', str(derived),
            'CODE_SIGN_IDENTITY=-', 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO',
            'ARCHS=arm64 x86_64', 'ONLY_ACTIVE_ARCH=NO', 'build',
        ], env=ENV, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    stage = attempt / 'image'
    stage.mkdir()
    app = stage / 'Adê.app'
    run('ditto', '--noqtn', '--norsrc', derived / 'Build/Products/Release/Ade.app', app)
    run('xattr', '-cr', app)
    entitlements = attempt / 'Distribution.entitlements'
    entitlements.write_bytes(plistlib.dumps(ENTITLEMENTS))
    run('codesign', '--force', '--sign', args.identity if signed else '-',
        '--timestamp' if signed else '--timestamp=none', '--options', 'runtime',
        '--entitlements', entitlements, app)
    info = verify(app, developer_id=signed)
    version = info['CFBundleShortVersionString']
    build = info['CFBundleVersion']
    if not re.fullmatch(r'[0-9.]+', version) or not re.fullmatch(r'[0-9]+', build):
        raise ValueError('Invalid distribution version')
    suffix = '' if signed else '-unsigned' if preview else '-local'
    name = f'Ade-{version}-{build}{suffix}.dmg'
    if signed:
        print('Notarizing application…', flush=True)
        archive = attempt / 'submission.zip'
        run('ditto', '-c', '-k', '--keepParent', app, archive)
        notarize(archive, args.notary_profile, attempt, 'app')
        run('xcrun', 'stapler', 'staple', app)
        run('xcrun', 'stapler', 'validate', app)
        run('spctl', '--assess', '--type', 'execute', app)
    (stage / 'Applications').symlink_to('/Applications')
    if preview:
        (stage / 'Instalación.txt').write_text(
            'Adê ' + version + ' (' + build + ') — macOS 14+\n\n'
            'Arrastra Adê a Aplicaciones. Reemplazar la app conserva sus datos locales.\n'
            'Esta edición usa firma ad hoc; no tiene Developer ID ni notarización de Apple.\n'
            'macOS puede bloquear su primera apertura. Consulta las instrucciones de Apple:\n'
            'https://support.apple.com/es-es/102445\n\n'
            'Drag Adê to Applications. Replacing the app preserves its local data.\n'
            'This preview is ad-hoc signed, without Developer ID or Apple notarization.\n'
            'macOS may block its first launch. Apple instructions:\n'
            'https://support.apple.com/en-us/102445\n', encoding='utf-8')
    image = attempt / name
    run('hdiutil', 'create', '-volname', 'Adê', '-srcfolder', stage,
        '-format', 'UDZO', '-fs', 'HFS+', image)
    if signed:
        print('Notarizing disk image…', flush=True)
        run('codesign', '--sign', args.identity, '--timestamp', image)
        notarize(image, args.notary_profile, attempt, 'dmg')
        run('xcrun', 'stapler', 'staple', image)
        run('xcrun', 'stapler', 'validate', image)
        run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', image)
    run('hdiutil', 'verify', image)
    destination = output / name
    os.replace(image, destination)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    (output / (name + '.sha256')).write_text(digest + '  ' + name + '\n')
    print(('Notarized distribution: ' if signed else 'Package (not notarized): ') + str(destination))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('local', help='Build an ad-hoc signed DMG for local verification')
    commands.add_parser('preview', help='Build a public preview DMG explicitly marked as not notarized')
    release = commands.add_parser('distribute', help='Build, sign, notarize and verify a public DMG')
    release.add_argument('--identity', required=True, help='Developer ID Application name or SHA-1')
    release.add_argument('--notary-profile', required=True, help='Existing notarytool Keychain profile')
    check = commands.add_parser('verify', help='Verify a universal Release application bundle')
    check.add_argument('app', type=pathlib.Path)
    check.add_argument('--developer-id', action='store_true')
    args = parser.parse_args()
    if args.command == 'verify':
        verify(args.app.resolve(), args.developer_id)
        print('Release bundle verified.')
    else:
        (ROOT / 'build').mkdir(exist_ok=True)
        package(args)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
