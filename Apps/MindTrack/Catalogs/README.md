# Bundled Japanese catalog

`japanese.db` (about 22 MB) is bundled with the app from this folder but is not in git. Build it with:

    python3 Scripts/build-japanese-catalog.py

That downloads JMdict, KANJIDIC2 and Tatoeba's Japanese sentences, English translations and indices
once (about 45 MB, cached in `~/Library/Caches/SystemJapaneseCatalog`) and builds in about twenty
seconds: 20,000 words in everyday order, about 85,000 example sentences with translations, and
3,100 kanji. Without it the app still works for maths, writing and reading; Japanese says the
catalog isn't installed.

Licences: JMdict and KANJIDIC2 are © the Electronic Dictionary Research and Development Group,
under CC BY-SA 4.0 (the derived database is shared alike); Tatoeba's sentences are CC BY 2.0 FR.
Keep the attribution in Settings.
