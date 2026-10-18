"""Count authored MoonBit source; generated files, examples and tests are excluded."""
from pathlib import Path
import json

root = Path(__file__).resolve().parent.parent
files = []
for path in sorted(root.rglob('*.mbt')):
    relative = path.relative_to(root)
    if any(part in {'_build','target','node_modules','.mooncakes','examples'} for part in relative.parts):
        continue
    if path.name.endswith(('_test.mbt','_wbtest.mbt')) or '.generated.' in path.name:
        continue
    lines = sum(1 for line in path.read_text(encoding='utf-8').splitlines() if line.strip() and not line.lstrip().startswith('//'))
    files.append({'file': str(relative).replace('\\','/'), 'lines': lines})
total = sum(item['lines'] for item in files)
print(json.dumps({'definition':'nonblank noncomment authored MoonBit lines; no tests examples generated files', 'production_lines':total,'files':files},indent=2))
if total < 4000:
    raise SystemExit('Expected at least 4000 production lines')
