# KaushalSetu – AI-assisted RPL assessment (SIH26242)

Flutter app + FastAPI backend. Worker self-declaration → automatic NSQF qualification-pack mapping →
generated practical checklist → photo/video evidence → AI-assisted suggestions → assessor scoring on a
standard 0–3 anchored rubric → competency profile + recommendation → **human sign-off**. Works offline and syncs later.

```
server/   FastAPI backend (SQLite). Catalogue data in server/data/qualification_packs/*.json
mobile/   Flutter app (sqflite offline store, sync queue, on-device mapper)
docs/     architecture, where AI supports vs. where the assessor decides, evaluation notes
```

## 1. Run the backend (PowerShell)
```powershell
cd server
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# assessor accounts (username:password:Display Name, comma separated). CHANGE THESE.
$env:KS_ASSESSORS = "assessor1:ChangeMe123:Asha Verma,assessor2:ChangeMe456:Ravi Patil"
# optional: LLM explanations + photo observations (advisory only)
# $env:GEMINI_API_KEY = "your-key"

uvicorn app.main:app --host 0.0.0.0 --port 8000
```
Check http://localhost:8000/api/health and http://localhost:8000/docs.
If `KS_ASSESSORS` is not set (dev only), `assessor1` / `assessor2` with password `assessor123` are created and a warning is logged.

Tests: `python -m pytest tests -q` (13 tests, all passing when this was delivered).

## 2. Run the app
```powershell
cd mobile
flutter clean
flutter pub get
flutter run -d emulator-5554
```
* Emulator reaches your PC at `http://10.0.2.2:8000` (default). Real phone: Settings → Server address → `http://<PC-IP>:8000`
  (same Wi-Fi, allow port 8000 in Windows Firewall).
* Worker flow works with **no server at all** (data saved on the phone, mapping done on-device). It syncs automatically when the server is reachable.
* Assessor sign-in needs the server.
* Run `flutter test` to check the on-device mapper, and `flutter analyze` – if anything is reported, send me the output and I will fix it.

## 3. Using your own data
* Replace/add trades: drop JSON files in `server/data/qualification_packs/` (same schema) or convert a CSV with
  `python scripts/import_qp_csv.py my_qp.csv`. Restart the server; the app downloads the new catalogue automatically.
  Then copy `GET /api/catalogue/export` to `mobile/assets/data/catalogue.json` if you want it bundled for first offline launch.
* Labelled declarations for mapping accuracy: `server/data/examples/declarations_*.csv`; run `python scripts/evaluate_matching.py`.
* Double-scored assessor data (organisers' dummy data): `python scripts/import_scores.py scores.csv`, then see Assessor → Agreement statistics.

## Honest status
See `docs/evaluation.md`. The qualification packs shipped here are **demo packs, not official NCVET documents**.
