# Bundled language catalogs

`japanese.db` (about 22 MB) and `spanish.db` (about 18 MB) are bundled with the app from this folder
but are not in git. Build them with:

    python3 Scripts/build-japanese-catalog.py
    python3 Scripts/build-spanish-catalog.py

The Japanese build downloads JMdict, KANJIDIC2 and Tatoeba's Japanese sentences, English translations
and indices once (about 45 MB, cached in `~/Library/Caches/SystemJapaneseCatalog`) and builds in about
twenty seconds: 20,000 words in everyday order, about 85,000 example sentences with translations, and
3,100 kanji.

The Spanish build downloads Wiktionary's Spanish entries from kaikki.org, the OpenSubtitles word
frequencies from FrequencyWords and Tatoeba's Spanish sentences and links once (about 105 MB, plus
Tatoeba's English sentences, shared with the Japanese cache when it's there; cached in
`~/Library/Caches/SystemSpanishCatalog`) and builds in about thirty seconds: about 15,000 words in the
order they're said, nouns with their article, and about 70,000 example sentences with translations.

Both catalogs share one schema, so the app reads them the same way. Without one, the app still works
for everything else; that language says its catalog isn't installed.

Licences: JMdict and KANJIDIC2 are © the Electronic Dictionary Research and Development Group,
under CC BY-SA 4.0. Wiktionary's text (via kaikki.org) and FrequencyWords' lists are CC BY-SA 4.0.
The derived databases are shared alike. Tatoeba's sentences are CC BY 2.0 FR. Keep the attribution
in Settings.
