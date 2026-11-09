#!/usr/bin/env python3
"""Exercise the packaged installation in isolated XDG directories, not user settings."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: tools/verify-linux-associations.py path/to/application.deb')
    package = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix='visor-mime-') as temporary:
        work = Path(temporary)
        root, control = work / 'root', work / 'control'
        run('dpkg-deb', '--extract', str(package), str(root))
        run('dpkg-deb', '--control', str(package), str(control))
        share = root / 'usr/share'
        metadata = json.loads((root / 'opt/visor-markdown/data/flutter_assets/assets/app_info.json').read_text())
        appid, binary = metadata['applicationId'], metadata['binary']
        desktop = share / 'applications' / f'{appid}.desktop'
        mime = share / 'mime/packages' / f'{appid}.xml'
        run('desktop-file-validate', str(desktop))
        assert mime.is_file()
        dependencies = subprocess.check_output(['dpkg-deb', '--field', str(package), 'Depends'], text=True)
        assert 'desktop-file-utils' in dependencies and 'shared-mime-info' in dependencies
        base = Path('/usr/share/mime/packages/freedesktop.org.xml')
        if base.exists():
            shutil.copy2(base, mime.parent / base.name)
        config = work / 'config'
        config.mkdir()
        defaults = config / 'mimeapps.list'
        defaults.write_text('[Default Applications]\ntext/markdown=previous-editor.desktop\n')
        original_defaults = defaults.read_bytes()
        (desktop.parent / 'previous-editor.desktop').write_text(
            '[Desktop Entry]\nType=Application\nName=Previous editor\nExec=true %F\nMimeType=text/markdown;\n')
        spybin = work / 'bin'
        spybin.mkdir()
        launcher = spybin / binary
        launcher.write_text('#!/usr/bin/python3\nimport json,os,sys\n'
                            'with open(os.environ["VISOR_ASSOCIATION_LAUNCH_LOG"],"w") as f: json.dump(sys.argv[1:],f)\n')
        launcher.chmod(0o755)
        env = dict(os.environ, XDG_DATA_HOME=str(share), XDG_DATA_DIRS=str(work / 'empty-data'),
                   XDG_CONFIG_HOME=str(config), XDG_CONFIG_DIRS=str(work / 'empty-config'),
                   XDG_CURRENT_DESKTOP='GNOME', PATH=str(spybin) + os.pathsep + os.environ['PATH'],
                   VISOR_ASSOCIATION_LAUNCH_LOG=str(work / 'launched.json'))
        files = [work / 'archivo con espacios.md', work / 'acentos á y % símbolos.markdown']
        for file in files:
            file.write_text('# Markdown\n', encoding='utf-8')

        def maintainer_script(name):
            script = (control / name).read_text().replace('/usr/share/', str(share) + '/')
            assert '/usr/share/' not in script.replace(str(share) + '/', '')
            run('sh', '-s', '--', 'configure' if name == 'postinst' else 'remove', input=script, env=env,
                stdout=subprocess.DEVNULL)

        maintainer_script('postinst')
        probe = r'''
import json, os, sys, time
from pathlib import Path
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio
appid = sys.argv[1]
apps = Gio.AppInfo.get_all_for_type('text/markdown')
ids = [a.get_id() for a in apps]
assert appid in ids, ids
assert Gio.AppInfo.get_default_for_type('text/markdown', False).get_id() == 'previous-editor.desktop'
for extension in ['md', 'markdown', 'mdown', 'mkd']:
    detected = Gio.content_type_guess('example.' + extension, b'# Markdown\n')[0]
    assert detected == 'text/markdown', (extension, detected)
app = next(a for a in apps if a.get_id() == appid)
assert app.supports_files() and app.should_show()
app.launch([Gio.File.new_for_path(f) for f in sys.argv[2:]], None)
log = Path(os.environ['VISOR_ASSOCIATION_LAUNCH_LOG'])
for _ in range(60):
    if log.exists(): break
    time.sleep(.05)
assert json.loads(log.read_text()) == sys.argv[2:]
print('GIO: registered for Markdown; extensions recognized; Open With preserves paths and Unicode; default unchanged.')
'''
        run('/usr/bin/python3', '-c', probe, f'{appid}.desktop', *map(str, files), env=env)
        assert defaults.read_bytes() == original_defaults
        desktop.unlink()
        mime.unlink()
        maintainer_script('postrm')
        run('/usr/bin/python3', '-c',
            'from gi.repository import Gio; import sys; '
            'assert sys.argv[1] not in [a.get_id() for a in Gio.AppInfo.get_all_for_type("text/markdown")]; '
            'assert Gio.AppInfo.get_default_for_type("text/markdown",False).get_id()=="previous-editor.desktop"',
            f'{appid}.desktop', env=env)
        assert defaults.read_bytes() == original_defaults
        print('Removal: MIME association cache refreshed; previous default preserved.')


if __name__ == '__main__':
    main()
