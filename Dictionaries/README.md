# Offline dictionaries

The keyboard reads these word lists without a network connection.
The word lists are separate data resources. The Source and Models folders retain the sources and licenses.

Upstream: https://github.com/LibreOffice/dictionaries
Revision: 892f0f402cf8347aa3273f774365c094c310cf1b

## Afrikaans

AfrikaansWords.txt contains 148,667 normalized surface forms.
The source comes from Translate.org.za and Puzzlefoundry.
Source/README_af_ZA.txt includes the copyright notices and LGPL 2.1 text.
Source/af_ZA.aff includes the current maintainer's notice.

Regenerate the list with `python3 scripts/prepare_afrikaans.py` from the project root.
The script verifies the source hashes and applies individual affix rules.
It omits compound-only entries, numbers, and punctuation outside word tokens.
It does not enumerate arbitrary compounds.

## German

GermanWords.txt contains 682,310 base words and individual affix forms.
The source uses the igerman98 and frami dictionaries.
Source/README_de_DE_frami.txt retains the authors' notices.
Source/COPYING_GPLv2 and Source/COPYING_GPLv3 retain the dictionary's license choices.

Regenerate the list with `python3 scripts/prepare_german.py` from the project root.
The script omits forbidden words and entries reserved for compounds or excluded from suggestions.
It does not implement compound rules, affix continuation, or cross-products.
The iOS German spelling checker also runs when its dictionary is available.

Each line stores a lowercase UTF-8 word.
A tab marks a German noun or name with an uppercase initial.
The keyboard preserves that initial in suggestions.
The word lists retain their own licenses.

## Runtime

The keyboard maps the files and keeps a compact line index.
It uses binary search for word recognition and prefix suggestions.
It generates single-edit spelling candidates for word tokens of 3 to 32 characters.
It normalizes case and canonical Unicode composition for lookup.
Provenance.json records the generated file hashes.

## English completions

An optional EnglishCompletions.txt table uses prefix candidates from Models/EnglishVocabulary.txt.
Check the vocabulary terms before using or distributing the table.
Generate it with `python3 scripts/prepare_english_completions.py` if you supply a compatible vocabulary.
The bundled supplemental English table works with the default build.
Each row stores a lowercase prefix and up to eight candidates, separated by tabs.
Candidates retain their original display forms and source frequency order.
Keys use canonical Unicode composition and UTF-8 byte order.
The table supports suggestions. It does not replace system spelling checks or corrections.


## Western language tables

Western contains common-word and short-prefix tables for nine additional languages.
The tables cover Spanish, French, Italian, Portuguese, Dutch, Swedish, Danish, Norwegian Bokmal, and Finnish.
They derive from wordfreq 3.1.1, by Robyn Speer.
These frequency tables describe usage. They are not authoritative spelling dictionaries.

Run `python3 scripts/prepare_western_words.py` with the pinned requirements in scripts/requirements-dictionaries.txt.
The generator uses installed package data. It makes no network request.
It keeps Latin-script words, canonical composition, and common frequencies.
It removes strong cross-language imports using the recorded frequency ratio.
Each language retains at most 30,000 words.
The prefix tables retain at most eight candidates for prefixes of one to four characters.
Longer prefixes use word-table lookup.
Western/Provenance.json records the version, input hashes, generation limits, and output hashes.

The generated Western data uses CC-BY-SA 4.0.
Western/Wordfreq-credits.txt retains source credits, changes, and upstream citations.
Western/CC-BY-SA-4.0.txt retains the data license.
Western/Wordfreq-code-license.txt retains the upstream code license notice.
The app's About page displays these notices.
Review distribution terms and public source access before an App Store release.

## Supplemental English usage data

Western/EnglishRanked.txt contains 52,631 frequency-ordered words from wordfreq 3.1.1.
Western/EnglishWords.txt stores the same words in lookup order for direct file mapping.
Western/EnglishSupplementCompletions.txt supplies up to eight candidates for each prefix.
Run `python3 scripts/prepare_english_words.py` to rebuild these files.
The generator uses installed package data and a minimum Zipf frequency of 2.5.
Western/EnglishProvenance.json records the source and generated hashes.
The existing Western credits and CC-BY-SA 4.0 license apply to these files.
These usage tables can include misspellings. They do not establish spelling validity.
