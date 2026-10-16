# Evaluation notes (read before presenting results)

**Mapping accuracy.** `python scripts/evaluate_matching.py` → 17/17 top-1 on `declarations_test.csv`.
Caveat: both CSVs were written by the developer of this prototype in the same vocabulary as the pack keywords, so this
number is optimistic. Re-run on declarations collected from real workers before quoting it. Adding the 24 training
examples to the index made no measurable difference on this small set.

**Scoring hints.** Indicator keyword matching is transparent but shallow: it cannot tell a keyword list from a real
explanation. That is why it is a hint, why level 3 needs evidence, and why assessors decide.

**Consistency improvement.** The code measures it (quadratic weighted kappa, ICC(1,1), % exact/within-1) and separates
*assisted* from *blind* scoring. No real double-scored data was available here, so the app reports "needs data" until
two assessors score the same workers in both modes. Unit tests verify the maths against scikit-learn.

**Not done / not verified**
* The Flutter code could not be compiled in the authoring environment (no Flutter SDK). Run `flutter analyze` and `flutter test`.
* Gemini / Ollama integration is written but untested without a key/server; the system works without it.
* Qualification packs are demo content (`verified: false`); criteria are available in English + Hindi (Marathi falls back to Hindi).
* No voice input yet; the PDF report is English-only (reportlab cannot shape Devanagari).
* Evidence is stored on the server disk (SQLite + files): fine for a pilot, use Postgres/object storage at scale.
