#!/usr/bin/env python3
"""Build the offline catalog from the official Unicode 17.0 files.

Inputs: https://www.unicode.org/Public/17.0.0/ucd/Blocks.txt
        https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedName.txt
        https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt
"""
import argparse
import gzip
import io
from pathlib import Path


def records(path):
    for line in path.read_text(encoding='utf-8').splitlines():
        data = line.split('#', 1)[0].strip()
        if data:
            yield tuple(part.strip() for part in data.split(';'))


def bounds(value):
    first, _, last = value.partition('..')
    return int(first, 16), int(last or first, 16)


def generate(blocks_path, names_path, emoji_path):
    blocks = [(bounds(code), name) for code, name in records(blocks_path)]
    block_index = 0
    current_group = None
    for code, name in records(names_path):
        first, last = bounds(code)
        while first <= last:
            while first > blocks[block_index][0][1]:
                block_index += 1
            (_, block_end), block_name = blocks[block_index]
            if block_name != current_group:
                yield f'b\t{block_name}'
                current_group = block_name
            end = min(last, block_end)
            code_range = f'{first:X}' if first == end else f'{first:X}..{end:X}'
            yield f'{code_range}\t{name}'
            first = end + 1

    for line in emoji_path.read_text(encoding='utf-8').splitlines():
        if line.startswith('# group: '):
            yield f'e\t{line.removeprefix("# group: ")}'
        elif '; fully-qualified' in line:
            data, description = line.split('#', 1)
            codes = data.split(';', 1)[0].strip()
            name = description.split(maxsplit=2)[2]
            yield f'{codes}\t{name}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ('blocks', 'names', 'emoji', 'output'):
        parser.add_argument(argument, type=Path)
    args = parser.parse_args()
    with args.output.open('wb') as output:
        with gzip.GzipFile(fileobj=output, mode='wb', mtime=0) as compressed:
            with io.TextIOWrapper(compressed, encoding='utf-8', newline='\n') as catalog:
                for line in generate(args.blocks, args.names, args.emoji):
                    catalog.write(line + '\n')


if __name__ == '__main__':
    main()
