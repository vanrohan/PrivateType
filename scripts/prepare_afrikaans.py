"""Build offline surface forms from the pinned Afrikaans Hunspell data."""
import hashlib
import json
import pathlib
import re
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Dictionaries" / "Source"
EXPECTED = {
    "af_ZA.dic": "8d806f90146059ea18b49c2352d188bd27dcc571a06815794facaa176aa5a5de",
    "af_ZA.aff": "fdfcdd04d700fc4ac94be63930167fa942ee5ffb471b52a6f4e0c68362dd63d2",
}
for name, digest in EXPECTED.items():
    assert hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() == digest, name

rules = {}
for line in (SOURCE / "af_ZA.aff").read_text().splitlines():
    parts = line.split()
    if len(parts) >= 5 and parts[0] in {"PFX", "SFX"}:
        kind, flag, strip, addition, condition = parts[:5]
        assert "/" not in addition, "Continuation flags need explicit support."
        rules.setdefault(flag, []).append((kind, "" if strip == "0" else strip,
                                          "" if addition == "0" else addition, condition))

words = set()
def add(word):
    word = unicodedata.normalize("NFC", word.lower())
    if (word and len(word) <= 32 and word[0].isalpha() and word[-1].isalpha()
            and all(c.isalpha() or c in "'\u2019" for c in word)):
        words.add(word)

for line in (SOURCE / "af_ZA.dic").read_text().splitlines()[1:]:
    fields = line.split()
    if not fields:
        continue
    entry = fields[0]
    word, _, flags = entry.partition("/")
    if "c" in flags:
        continue
    add(word)
    # This dictionary has no cross-product suffix rules.
    for flag in flags:
        for kind, strip, addition, condition in rules.get(flag, []):
            if kind == "PFX":
                if word.startswith(strip) and re.search("^(?:" + condition + ")", word):
                    add(addition + word[len(strip):])
            elif word.endswith(strip) and re.search("(?:" + condition + ")$", word):
                add((word[:-len(strip)] if strip else word) + addition)

output = ROOT / "Dictionaries" / "AfrikaansWords.txt"
output.write_text("\n".join(sorted(words)) + "\n")
print(json.dumps({"words": len(words), "bytes": output.stat().st_size,
                  "sha256": hashlib.sha256(output.read_bytes()).hexdigest()}))
