"""Build offline word tables from the pinned wordfreq package."""

import hashlib
from importlib.metadata import distribution
import json
from pathlib import Path
import unicodedata

from wordfreq import available_languages, get_frequency_dict, top_n_list
from prepare_english_completions import completion_table

VERSION = "3.1.1"
LANGUAGES = ["es", "fr", "it", "pt", "nl", "sv", "da", "nb", "fi"]
ROOT = Path(__file__).resolve().parents[1]


def is_word(word):
    return (word and len(word) <= 32 and word[0].isalpha() and word[-1].isalpha()
            and all((character.isalpha() and "LATIN" in unicodedata.name(character, ""))
                    or character in "'\u2019" for character in word))


def main():
    package = distribution("wordfreq")
    if package.version != VERSION:
        raise RuntimeError("Use wordfreq==" + VERSION)
    output = ROOT / "Dictionaries" / "Western"
    output.mkdir(parents=True, exist_ok=True)
    frequencies = {code: get_frequency_dict(code) for code in ["en", "de"] + LANGUAGES}
    records = {}
    for code in LANGUAGES:
        words = []
        seen = set()
        for original in top_n_list(code, 50_000):
            word = unicodedata.normalize("NFC", original.lower())
            frequency = frequencies[code].get(word, 0)
            if not is_word(word) or word in seen or frequency < 10 ** -6.5:
                continue
            if max(table.get(word, 0) for table in frequencies.values()) > frequency * 20:
                continue
            seen.add(word)
            words.append(word)
            if len(words) == 30_000:
                break
        values = {
            code + "Words.txt": "\n".join(sorted(words, key=lambda word: word.encode("utf-8"))) + "\n",
            code + "Completions.txt": "".join(line + "\n" for line in completion_table(words).splitlines()
                                               if len(line.split("\t")[0]) <= 4),
        }
        for name, text in values.items():
            path = output / name
            path.write_text(text, encoding="utf-8")
            records[name] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                             "entries": len(text.splitlines()), "bytes": path.stat().st_size}
    metadata = package.read_text("METADATA")
    license_start = metadata.index("## License")
    (output / "Wordfreq-credits.txt").write_text(
        "Source: https://github.com/rspeer/wordfreq\nVersion: " + VERSION + "\n"
        "Author: Robyn Speer\nData license: Creative Commons Attribution-ShareAlike 4.0\n"
        "https://creativecommons.org/licenses/by-sa/4.0/\n"
        "Changes: normalized, filtered, frequency ordered, and converted into word and prefix tables.\n\n"
        + metadata[license_start:], encoding="utf-8")
    (output / "Wordfreq-code-license.txt").write_text(package.read_text("LICENSE.txt"), encoding="utf-8")
    manifest = {"source": "https://github.com/rspeer/wordfreq", "version": VERSION,
                "data_license": "CC-BY-SA-4.0", "max_words": 30000, "max_prefix": 4,
                "sources": {code: {"file": Path(available_languages()[code]).name,
                                   "sha256": hashlib.sha256(Path(available_languages()[code]).read_bytes()).hexdigest()}
                            for code in frequencies},
                "minimum_zipf": 2.5, "maximum_cross_language_frequency_ratio": 20, "generated": records}
    (output / "Provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({name: record["entries"] for name, record in records.items()}))


if __name__ == "__main__":
    main()
