"""Build the standalone release app: dist/Makro OASA.app and dist/Makro-OASA-<version>-macOS.zip

Run with the project's Python (the oasa-gui conda env):
    /opt/anaconda3/envs/oasa-gui/bin/python tools/build_app.py

Steps:
 1. py2app (full build: Python and every package copied into the app)
 2. copy in the shared libraries conda's Python links as @rpath/... (libffi, OpenSSL, zlib…),
    which py2app leaves out, so the app runs on a Mac without this conda env
 3. ad-hoc code-sign every library and the app (required on Apple Silicon after changing them)
 4. zip it for a GitHub release
"""
import os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, 'dist', 'Makro OASA.app')
PREFIX = sys.prefix  # the conda env the libraries come from
LIB_SRC = os.path.join(PREFIX, 'lib')


def run(*cmd, **kw):
    print('$', ' '.join(cmd))
    return subprocess.run(cmd, check=True, **kw)


def macho_files(root):
    for d, _, files in os.walk(root):
        for f in files:
            p = os.path.join(d, f)
            if not os.path.islink(p) and (f.endswith(('.so', '.dylib')) or os.access(p, os.X_OK)):
                yield p


def rpath_deps(path):
    out = subprocess.run(['otool', '-L', path], capture_output=True, text=True).stdout
    return re.findall(r'^\s+@rpath/(\S+)', out, re.M)


def bundle_rpath_libs():
    """Copy every @rpath library the bundle needs (and what those need) into Contents/Resources/lib.

    Python's extension modules look for @rpath at @loader_path/../../ = Contents/Resources/lib."""
    dest = os.path.join(APP, 'Contents', 'Resources', 'lib')
    present = {f for _, _, fs in os.walk(os.path.join(APP, 'Contents')) for f in fs}
    todo = [p for p in macho_files(os.path.join(APP, 'Contents'))]
    copied = []
    while todo:
        for dep in rpath_deps(todo.pop()):
            name = os.path.basename(dep)
            if name in present or name.startswith('libpython'):
                continue
            src = os.path.realpath(os.path.join(LIB_SRC, name))
            if not os.path.exists(src):
                print(f'  ! {name} not found in {LIB_SRC}')
                continue
            target = os.path.join(dest, name)
            shutil.copy2(src, target)
            os.chmod(target, 0o755)
            subprocess.run(['install_name_tool', '-add_rpath', '@loader_path', target], capture_output=True)
            present.add(name)
            copied.append(name)
            todo.append(target)
    print('  bundled:', ', '.join(sorted(copied)) or 'nothing')


def sign():
    """Ad-hoc sign every library, then the app. `codesign --deep` skips Contents/Resources/lib,
    and a library with a stale signature gets the app killed on Apple Silicon ("Code Signature Invalid")."""
    libs = [p for p in macho_files(os.path.join(APP, 'Contents')) if p.endswith(('.so', '.dylib'))]
    for p in libs:
        subprocess.run(['codesign', '--force', '--sign', '-', p], check=True, capture_output=True)
    print(f'  signed {len(libs)} libraries')
    run('codesign', '--force', '--sign', '-', APP)
    run('codesign', '--verify', '--deep', '--strict', APP)


def version():
    with open(os.path.join(ROOT, 'setup.py'), encoding='utf-8') as f:
        return re.search(r"VERSION = '([^']+)'", f.read()).group(1)


def main():
    os.chdir(ROOT)
    shutil.rmtree('build', ignore_errors=True)
    shutil.rmtree('dist', ignore_errors=True)
    run(sys.executable, 'setup.py', 'py2app', stdout=subprocess.DEVNULL)
    bundle_rpath_libs()
    sign()
    zip_path = os.path.join(ROOT, 'dist', f'Makro-OASA-{version()}-macOS.zip')
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', APP, zip_path)
    print('built', APP)
    print('zipped', zip_path, f'({os.path.getsize(zip_path) / 1e6:.1f} MB)')


if __name__ == '__main__':
    main()
