#!/usr/bin/env python3
"""Validate release metadata and derive Flutter and package versions."""
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
FIELDS = (
    'name', 'version', 'buildDate', 'author', 'licenseName', 'licenseSpdx',
    'licenseUrl', 'repository', 'issues', 'applicationId', 'binary',
)
LANGUAGES = ('en', 'es', 'pt', 'de', 'fr', 'it')
VERSION = re.compile(r'([0-9]+\.[0-9]+\.[0-9]+)(?:-([0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*))?')


def required_text(value, key):
    if not isinstance(value, str) or not value.strip() or re.search(r'[\x00-\x1f\x7f]', value):
        raise ValueError(f'invalid or missing field: {key}')
    return value


def read(path):
    data = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(data, dict):
        raise ValueError('expected a JSON object')
    for key in FIELDS:
        required_text(data.get(key), key)
    version = VERSION.fullmatch(data['version'])
    if not version:
        raise ValueError('invalid field: version')
    if type(data.get('buildNumber')) is not int or data['buildNumber'] < 1:
        raise ValueError('invalid or missing field: buildNumber')
    descriptions = data.get('descriptions')
    if not isinstance(descriptions, dict):
        raise ValueError('invalid or missing field: descriptions')
    for language in LANGUAGES:
        required_text(descriptions.get(language), f'descriptions.{language}')
    for key, pattern in (
        ('binary', r'[a-z0-9][a-z0-9-]+'),
        ('applicationId', r'[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+'),
        ('licenseSpdx', r'[A-Za-z0-9][A-Za-z0-9.+-]*'),
    ):
        if not re.fullmatch(pattern, data[key]):
            raise ValueError(f'invalid field: {key}')
    return data, version.groups()


def sync():
    data, (base, prerelease) = read(ROOT / 'assets/app_info.json')
    version = base + (f'-{prerelease}' if prerelease else '')
    manifest = ROOT / 'pubspec.yaml'
    original = manifest.read_text(encoding='utf-8')
    updated, count = re.subn(
        r'^version:[^\n]*$', f"version: {version}+{data['buildNumber']}",
        original, flags=re.MULTILINE,
    )
    if count != 1:
        raise ValueError('expected exactly one version field in pubspec.yaml')
    if updated != original:
        manifest.write_text(updated, encoding='utf-8')


def package(metadata, output=None):
    data, (base, prerelease) = read(metadata)
    version = data['version']
    if output is None:
        # DEB and RPM need the beta to sort before the corresponding final release.
        native = base + (f"~{prerelease.replace('-', '.')}" if prerelease else '')
        print(version, native, *(data[key] for key in (
            'name', 'author', 'licenseSpdx', 'applicationId', 'binary', 'repository',
        )), data['descriptions']['en'], sep='\n')
        return
    for language in LANGUAGES:
        (output / f'DESCRIPTION.{language}.md').write_text(
            f"# {data['name']} {data['version']}\n\n{data['descriptions'][language]}\n\n"
            f"{data['author']} · [{data['licenseName']}]({data['licenseUrl']}) "
            f"({data['licenseSpdx']})\n\n{data['repository']}\n",
            encoding='utf-8',
        )


if __name__ == '__main__':
    try:
        match sys.argv[1:]:
            case ['sync']:
                sync()
            case ['package', metadata, *output] if len(output) <= 1:
                package(Path(metadata), Path(output[0]) if output else None)
            case _:
                raise ValueError('usage: app-info.py sync | package METADATA [OUTPUT]')
    except (ValueError, OSError) as error:
        sys.exit(f'Application metadata: {error}')
