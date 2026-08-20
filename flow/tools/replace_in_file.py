import re
from pathlib import Path

def replace_in_file(filepath: Path, x: dict[str,str]):
    pattern = re.compile('|'.join(re.escape(k) for k in sorted(x, key=len, reverse=True)))
    content = filepath.read_text()
    filepath.write_text(pattern.sub(lambda m: x[m.group(0)], content))

def replace_regex(filepath: Path, x: dict[str,str], flags=0):
    content = filepath.read_text()
    for k in sorted(x, key=len, reverse=True):
        content = re.sub(k, x[k], content, flags=flags)
    filepath.write_text(content)
