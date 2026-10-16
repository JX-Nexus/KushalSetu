import uuid

import pytest

GOOD_SAFETY = ("First I close the main valve, wear gloves, goggles and safety shoes, cover the floor "
               "and switch off the mcb near the wet area. I use a blow torch only with ventilation and clean up the waste after.")


def uid():
    return str(uuid.uuid4())


def hdr(tok):
    return {"Authorization": f"Bearer {tok}"}


def worker_login(client, name="Ramesh"):
    wid = uid()
    r = client.post("/api/auth/worker", json={"id": wid, "name": name, "phone": "98 765-43210", "language": "en"})
    assert r.status_code == 200, r.text
    return wid, r.json()["token"]


def assessor_login(client, user="a1", pw="pw1"):
    r = client.post("/api/auth/assessor", json={"username": user, "password": pw})
    assert r.status_code == 200, r.text
    return r.json()["token"]


def make_bundle(wid, aid, qp=None, status="in_progress", answers=None, text="I am a plumner, 5 years fitting taps, pipes and bathroom fittings in houses"):
    return {"worker": {"id": wid, "name": "Ramesh", "language": "en"},
            "assessment": {"id": aid, "worker_id": wid, "language": "en", "declaration_text": text, "declared_years": 5,
                           "qp_code": qp, "status": status},
            "responses": [{"id": uid(), "criterion_id": cid, "answer_text": t} for cid, t in (answers or {}).items()]}


def test_health_and_catalogue(client):
    h = client.get("/api/health").json()
    assert h["packs"] == 4 and h["criteria"] == 24
    cat = client.get("/api/catalogue?lang=hi").json()
    assert any("प्लंबर" in p["title"] for p in cat["packs"])
    exp = client.get("/api/catalogue/export").json()
    assert exp["version"] == h["catalogue_version"] and len(exp["packs"]) == 4
    assert client.get("/api/catalogue/NOPE/checklist").status_code == 404
    assert client.get("/api/rubric").json()["scale"][3]["score"] == 3
    assert client.get("/api/ai/status").json()["mapping_engine"]["packs_indexed"] == 4


def test_auth_rules(client):
    assert client.post("/api/auth/assessor", json={"username": "a1", "password": "bad"}).status_code == 401
    assert client.get("/api/assessor/queue").status_code == 401
    _, wtok = worker_login(client)
    assert client.get("/api/assessor/queue", headers=hdr(wtok)).status_code == 403
    assert client.get("/api/assessor/queue", headers={"Authorization": "Bearer garbage"}).status_code == 401


def test_mapping_endpoint(client):
    _, tok = worker_login(client)
    r = client.post("/api/map", json={"text": "main raj mistri hu, eent ki chinai aur plaster karta hu", "language": "hi"}, headers=hdr(tok)).json()
    assert r["matches"][0]["qp_code"] == "KS-MSN-L3"
    r = client.post("/api/map", json={"text": "मैं वेल्डिंग करता हूँ", "language": "hi"}, headers=hdr(tok)).json()
    assert r["matches"][0]["qp_code"] == "KS-WLD-L4"
    r = client.post("/api/map", json={"text": "   ", "language": "en"}, headers=hdr(tok)).json()
    assert r["matches"] == [] and r["confidence"] == "none"
    r = client.post("/api/map", json={"text": "I like cricket and cooking", "language": "en"}, headers=hdr(tok)).json()
    assert r["confidence"] == "low"


def test_full_workflow_two_assessors(client):
    wid, wtok = worker_login(client)
    aid = uid()
    # push in progress with answers, mapping is computed server-side
    ans = {"PLB-N1-C1": GOOD_SAFETY, "PLB-N1-C2": "I work in residential areas.", "PLB-N2-C1": "GI, CPVC, UPVC, PPR and copper; hot water uses CPVC; elbow tee union and coupler fittings",
           "PLB-N2-C2": "measure and cut square, remove burr, thread with ptfe tape, clamp the pipe with proper slope for drain",
           "PLB-N3-C1": "close outlets, fill and pressure test with gauge hold for 2 hours, inspect every joint",
           "PLB-N3-C2": "change washer or cartridge for dripping tap; plunger or snake for choke; check strainer and tank for low pressure"}
    r = client.post("/api/sync/push", json=make_bundle(wid, aid, qp=None, answers=ans), headers=hdr(wtok))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["match"]["matches"][0]["qp_code"] == "KS-PLB-L4"
    assert body["accepted"] == [] and body["qp_code"] is None  # no pack chosen yet, so answers are not accepted

    # worker confirms pack, pushes again (idempotent) and submits
    r = client.post("/api/sync/push", json=make_bundle(wid, aid, qp="KS-PLB-L4", answers=ans), headers=hdr(wtok)).json()
    assert len(r["accepted"]) == 6 and r["rejected"] == []
    r = client.post("/api/sync/push", json=make_bundle(wid, aid, qp="KS-PLB-L4", answers=ans), headers=hdr(wtok)).json()  # idempotent retry
    assert len(r["accepted"]) == 6

    # reject unknown pack and foreign criteria
    assert client.post("/api/sync/push", json=make_bundle(wid, uid(), qp="XXX"), headers=hdr(wtok)).status_code == 422
    other = make_bundle(wid, aid, qp="KS-PLB-L4", answers={"ELE-N1-C1": "x"})
    assert client.post("/api/sync/push", json=other, headers=hdr(wtok)).json()["rejected"] == ["ELE-N1-C1"]

    # impersonation blocked
    _, wtok2 = worker_login(client, "Other")
    assert client.post("/api/sync/push", json=make_bundle(wid, aid, qp="KS-PLB-L4"), headers=hdr(wtok2)).status_code == 403
    assert client.get(f"/api/assessments/{aid}", headers=hdr(wtok2)).status_code == 403

    # evidence upload (png header bytes), idempotent, bad types rejected
    eid = uid()
    png = b"\x89PNG\r\n\x1a\n" + b"0" * 300
    files = {"file": ("p.png", png, "image/png")}
    form = {"id": eid, "assessment_id": aid, "criterion_id": "PLB-N1-C1", "kind": "photo"}
    r = client.post("/api/evidence", data=form, files=files, headers=hdr(wtok))
    assert r.status_code == 200 and not r.json()["duplicate"], r.text
    assert client.post("/api/evidence", data=form, files={"file": ("p.png", png, "image/png")}, headers=hdr(wtok)).json()["duplicate"]
    oct_ = client.post("/api/evidence", data={**form, "id": uid()}, files={"file": ("shot.jpg", png, "application/octet-stream")}, headers=hdr(wtok))
    assert oct_.status_code == 200, oct_.text
    bad = client.post("/api/evidence", data={**form, "id": uid()}, files={"file": ("x.pdf", b"%PDF", "application/pdf")}, headers=hdr(wtok))
    assert bad.status_code == 415
    wrong = client.post("/api/evidence", data={**form, "id": uid(), "criterion_id": "ELE-N1-C1"}, files={"file": ("p.png", png, "image/png")}, headers=hdr(wtok))
    assert wrong.status_code == 422

    # assessors cannot score before submission
    atok = assessor_login(client)
    assert client.put(f"/api/assessor/assessments/{aid}/scores", json={"scores": []}, headers=hdr(atok)).status_code == 409

    # submit
    r = client.post("/api/sync/push", json=make_bundle(wid, aid, qp="KS-PLB-L4", status="submitted", answers=ans), headers=hdr(wtok)).json()
    assert r["status"] == "submitted"
    r = client.post("/api/sync/push", json=make_bundle(wid, aid, qp="KS-PLB-L4", status="in_progress", answers=ans), headers=hdr(wtok)).json()
    assert r["status"] == "submitted"  # never downgraded

    # worker cannot see AI hints; assessor can
    wd = client.get(f"/api/assessments/{aid}", headers=hdr(wtok)).json()
    assert "ai" not in wd["responses"]["PLB-N1-C1"] and "profile" not in wd
    queue = client.get("/api/assessor/queue", headers=hdr(atok)).json()
    assert any(q["id"] == aid for q in queue)
    ad = client.get(f"/api/assessments/{aid}", headers=hdr(atok)).json()
    ai = ad["responses"]["PLB-N1-C1"]["ai"]["rule"]
    assert ai["suggested_score"] == 3 and ad["responses"]["PLB-N1-C2"]["ai"]["rule"]["suggested_score"] <= 1
    assert ad["evidence"][0]["criterion_id"] == "PLB-N1-C1"
    assert ad["scores_source"] == "ai_provisional"

    # evidence file download is authenticated
    url = ad["evidence"][0]["url"]
    assert client.get(url).status_code == 401
    assert client.get(url + f"?token={atok}").content == png
    assert client.get(url + f"?token={wtok2}").status_code == 403

    # assessor 1 scores everything (assisted), assessor 2 scores blind
    crit = [c["id"] for n in ad["checklist"]["nos"] for c in n["criteria"]]
    s1 = {c: 3 for c in crit}
    s1["PLB-N1-C2"] = 2
    r = client.put(f"/api/assessor/assessments/{aid}/scores", headers=hdr(atok),
                   json={"aids_shown": True, "scores": [{"criterion_id": c, "score": v} for c, v in s1.items()]})
    assert r.status_code == 200, r.text
    assert r.json()["profile"]["recommendation"]["code"] == "recommend_certification"
    assert r.json()["status"] == "under_review"
    atok2 = assessor_login(client, "a2", "pw2")
    s2 = {c: 3 for c in crit}
    s2["PLB-N1-C2"] = 1
    s2["PLB-N3-C2"] = 2
    client.put(f"/api/assessor/assessments/{aid}/scores", headers=hdr(atok2),
               json={"aids_shown": False, "scores": [{"criterion_id": c, "score": v} for c, v in s2.items()]})

    # worker pushes are locked while under review
    assert client.post("/api/sync/push", json=make_bundle(wid, aid, qp="KS-PLB-L4", answers=ans), headers=hdr(wtok)).json()["locked"] is True

    # sign-off: override requires reasoning; agreeing doesn't
    r = client.post(f"/api/assessor/assessments/{aid}/sign-off", json={"decision": "not_yet", "reasoning": ""}, headers=hdr(atok))
    assert r.status_code == 422
    assert client.post(f"/api/assessor/assessments/{aid}/sign-off", json={"decision": "bogus"}, headers=hdr(atok)).status_code == 422
    r = client.post(f"/api/assessor/assessments/{aid}/sign-off", json={"decision": "certify", "reasoning": ""}, headers=hdr(atok))
    assert r.status_code == 200 and r.json()["overridden"] is False and r.json()["status"] == "signed_off"
    assert client.put(f"/api/assessor/assessments/{aid}/scores", json={"scores": [{"criterion_id": "PLB-N1-C1", "score": 0}]}, headers=hdr(atok)).status_code == 409

    # worker now sees result + profile + PDF; others can't
    wd = client.get(f"/api/assessments/{aid}", headers=hdr(wtok)).json()
    assert wd["result"]["decision"] == "certify" and wd["profile"]["overall_pct"] > 90
    pdf = client.get(f"/api/assessments/{aid}/report.pdf", headers=hdr(wtok))
    assert pdf.status_code == 200 and pdf.content[:4] == b"%PDF"
    assert client.get(f"/api/assessments/{aid}/report.pdf", headers=hdr(wtok2)).status_code == 403

    # agreement analytics: one assisted-vs-blind mix -> no pairs in either bucket yet
    rep = client.get("/api/analytics/agreement", headers=hdr(atok)).json()
    assert rep["total_scores"] == 12 and rep["ai_vs_assessor"]["n_pairs"] > 0
    assert rep["assisted"]["n_pairs"] == 0 and rep["unassisted"]["n_pairs"] == 0


def test_critical_failure_and_more_evidence(client):
    wid, wtok = worker_login(client)
    aid = uid()
    client.post("/api/sync/push", json=make_bundle(wid, aid, qp="KS-ELE-L4", status="submitted", text="electrician wiring"), headers=hdr(wtok))
    atok = assessor_login(client)
    crit = ["ELE-N1-C1", "ELE-N1-C2", "ELE-N2-C1", "ELE-N2-C2", "ELE-N3-C1", "ELE-N3-C2"]
    scores = {c: 3 for c in crit}
    scores["ELE-N1-C1"] = 1   # critical safety criterion below 2
    r = client.put(f"/api/assessor/assessments/{aid}/scores", headers=hdr(atok),
                   json={"scores": [{"criterion_id": c, "score": v} for c, v in scores.items()]}).json()
    n1 = r["profile"]["nos"][0]
    assert n1["critical_failure"] and not n1["passed"]
    assert r["profile"]["recommendation"]["code"] != "recommend_certification"
    # request more evidence needs reasoning, then unlocks the worker
    assert client.post(f"/api/assessor/assessments/{aid}/sign-off", json={"decision": "more_evidence"}, headers=hdr(atok)).status_code == 422
    r = client.post(f"/api/assessor/assessments/{aid}/sign-off", json={"decision": "more_evidence", "reasoning": "Need a photo of the isolation procedure"}, headers=hdr(atok))
    assert r.json()["status"] == "needs_evidence"
    r = client.post("/api/sync/push", json=make_bundle(wid, aid, qp="KS-ELE-L4", status="submitted", text="electrician wiring",
                                                       answers={"ELE-N1-C1": "switch off mcb, test with tester, wear rubber gloves"}), headers=hdr(wtok)).json()
    assert r["locked"] is False and r["status"] == "submitted"


def test_incomplete_cannot_certify(client):
    wid, wtok = worker_login(client)
    aid = uid()
    client.post("/api/sync/push", json=make_bundle(wid, aid, qp="KS-WLD-L4", status="submitted", text="welder"), headers=hdr(wtok))
    atok = assessor_login(client)
    client.put(f"/api/assessor/assessments/{aid}/scores", headers=hdr(atok), json={"scores": [{"criterion_id": "WLD-N1-C1", "score": 3}]})
    r = client.post(f"/api/assessor/assessments/{aid}/sign-off", json={"decision": "certify", "reasoning": ""}, headers=hdr(atok))
    assert r.status_code == 409
