"""Build supplemental English spelling data without changing model indices."""

import hashlib
from importlib.metadata import version
import json
from pathlib import Path

from wordfreq import available_languages, top_n_list, zipf_frequency
from prepare_english_completions import completion_table
from prepare_western_words import is_word


def main():
    if version("wordfreq") != "3.1.1":
        raise RuntimeError("Use wordfreq==3.1.1")
    root = Path(__file__).resolve().parents[1]
    output = root / "Dictionaries" / "Western"
    words = [word for word in top_n_list("en", 100_000)
             if is_word(word) and zipf_frequency(word, "en") >= 2.5]
    files = {"EnglishRanked.txt": "\n".join(words) + "\n",
             "EnglishWords.txt": "\n".join(sorted(words, key=lambda word: word.encode("utf-8"))) + "\n",
             "EnglishSupplementCompletions.txt": completion_table(words)}
    records = {}
    for name, text in files.items():
        data = text.encode("utf-8")
        (output / name).write_bytes(data)
        records[name] = {"sha256": hashlib.sha256(data).hexdigest(), "entries": len(text.splitlines())}
    source = Path(available_languages()["en"])
    provenance = {"source": "https://github.com/rspeer/wordfreq", "version": "3.1.1",
                  "data_license": "CC-BY-SA-4.0", "minimum_zipf": 2.5,
                  "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "generated": records}
    (output / "EnglishProvenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(records))


if __name__ == "__main__":
    main()
