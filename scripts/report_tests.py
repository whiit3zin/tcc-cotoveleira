"""Expose the xcresult summary through public Actions annotations, without secrets."""
import json
import pathlib
import sys


def notice(title, data):
    message = json.dumps(data, ensure_ascii=False).replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print(f'::notice title={title}::{message}')


root = pathlib.Path(sys.argv[1])
for path in root.rglob('test-summary.json'):
    data = json.loads(path.read_text())
    notice('XCTest summary', data)
for path in root.rglob('test-tree.json'):
    notice('XCTest details', json.loads(path.read_text()))
