"""Build a compact German base-word fallback from pinned Hunspell data."""
import hashlib
import json
import pathlib
import re
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Dictionaries" / "Source" / "de_DE_frami.dic"
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == "52d2484a70681386d979e958f2f828a976f0dcdaa680038f371bc70abcf7463a"
rules = {}
for line in (SOURCE.parent / "de_DE_frami.aff").read_text(encoding="iso8859-1").splitlines():
    fields = line.split()
    if len(fields) >= 5 and fields[0] in {"PFX", "SFX"}:
        kind, flag, strip, addition, condition = fields[:5]
        addition, _, continuation = addition.partition("/")
        if any(flag in continuation for flag in "dohn"):
            continue
        rules.setdefault(flag, []).append((kind, "" if strip == "0" else strip,
                                          "" if addition == "0" else addition, condition))
words = {}
def add(word):
    word = unicodedata.normalize("NFC", word)
    if (word and len(word) <= 32 and word[0].isalpha() and word[-1].isalpha()
            and all(c.isalpha() or c in "'\u2019" for c in word)):
        lower = word.lower()
        words[lower] = words.get(lower, True) and word[0].isupper()

for line in SOURCE.read_text(encoding="iso8859-1").splitlines()[1:]:
    if not line.strip() or line.startswith("#"):
        continue
    word, _, flags = line.split()[0].partition("/")
    if any(flag in flags for flag in "don"):
        continue
    if "h" not in flags:
        add(word)
    for flag in flags:
        for kind, strip, addition, condition in rules.get(flag, []):
            if kind == "PFX":
                if word.startswith(strip) and re.search("^(?:" + condition + ")", word):
                    add(addition + word[len(strip):])
            elif word.endswith(strip) and re.search("(?:" + condition + ")$", word):
                add((word[:-len(strip)] if strip else word) + addition)
output = ROOT / "Dictionaries" / "GermanWords.txt"
output.write_text("".join(word + ("\t1" if words[word] else "") + "\n" for word in sorted(words)))
print(json.dumps({"words": len(words), "bytes": output.stat().st_size,
                  "sha256": hashlib.sha256(output.read_bytes()).hexdigest()}))
