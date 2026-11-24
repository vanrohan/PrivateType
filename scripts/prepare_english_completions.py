"""Build a prefix table from the existing English model vocabulary."""

import argparse
from pathlib import Path
import unicodedata


def completion_table(words):
    table = {}
    for original in words:
        word = unicodedata.normalize("NFC", original)
        if not word or len(word) > 32 or not word[0].isalpha() or not word[-1].isalpha():
            continue
        if not all(character.isalpha() or character in "'\u2019" for character in word):
            continue
        key = word.lower()
        for length in range(1, len(key)):
            candidates = table.setdefault(key[:length], {})
            if len(candidates) < 8:
                candidates.setdefault(key, original)
    return "".join(prefix + "\t" + "\t".join(table[prefix].values()) + "\n"
                   for prefix in sorted(table, key=lambda value: value.encode("utf-8")))


def write_completions(source, destination):
    text = completion_table(source.read_text(encoding="utf-8").splitlines())
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8")


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=root / "Models/EnglishVocabulary.txt")
    parser.add_argument("--destination", type=Path, default=root / "Dictionaries/EnglishCompletions.txt")
    args = parser.parse_args()
    write_completions(args.source, args.destination)


if __name__ == "__main__":
    main()
