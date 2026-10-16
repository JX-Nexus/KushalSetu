"""PDF competency report (reportlab). English-only text: reportlab cannot shape Devanagari,
so non-Latin characters in free text are replaced rather than rendered garbled."""
import io
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

TEAL = colors.HexColor("#00696B")
SCORE_LABEL = {0: "0 Not demonstrated", 1: "1 Partial", 2: "2 Minor guidance", 3: "3 Independent"}


def safe(s) -> str:
    if s is None:
        return ""
    out = "".join(ch if ord(ch) < 256 else "?" for ch in str(s))
    return escape(out)


def build_pdf(data: dict) -> bytes:
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=16 * mm, rightMargin=16 * mm, topMargin=14 * mm,
                            bottomMargin=14 * mm, title="KaushalSetu RPL Competency Profile")
    ss = getSampleStyleSheet()
    h1 = ParagraphStyle("h1", parent=ss["Title"], textColor=TEAL, fontSize=19, spaceAfter=4)
    h2 = ParagraphStyle("h2", parent=ss["Heading2"], textColor=TEAL, fontSize=12.5, spaceBefore=10, spaceAfter=4)
    body = ParagraphStyle("b", parent=ss["BodyText"], fontSize=9.5, leading=12.5)
    small = ParagraphStyle("s", parent=body, fontSize=8, textColor=colors.HexColor("#555555"))
    cell = ParagraphStyle("c", parent=body, fontSize=8.6, leading=10.8)

    w, a, p, rec = data["worker"], data["assessment"], data["profile"], data["profile"]["recommendation"]
    el = [Paragraph("KaushalSetu - RPL Competency Profile", h1),
          Paragraph("Assessment-support report. This is NOT an official certificate or qualification. "
                    "The recommendation below requires sign-off by a human assessor.", small), Spacer(1, 6)]

    info = [["Worker", safe(w.get("name")), "Phone", safe(w.get("phone") or "-")],
            ["Assessment ID", safe(a["id"][:13]), "Status", safe(a["status"])],
            ["Mapped qualification pack", safe(f"{p['qp_title']} ({p['qp_code']})"), "NSQF level", safe(p.get("nsqf_level"))]]
    t = Table(info, colWidths=[38 * mm, 62 * mm, 25 * mm, 51 * mm])
    t.setStyle(TableStyle([("FONTSIZE", (0, 0), (-1, -1), 8.8), ("TEXTCOLOR", (0, 0), (0, -1), TEAL),
                           ("TEXTCOLOR", (2, 0), (2, -1), TEAL), ("VALIGN", (0, 0), (-1, -1), "TOP"),
                           ("LINEBELOW", (0, 0), (-1, -1), 0.25, colors.lightgrey)]))
    el += [t, Paragraph("Recommendation", h2),
           Paragraph(f"<b>{safe(rec['label'])}</b>", body),
           Paragraph(f"Overall weighted score: <b>{p['overall_pct']}%</b> &nbsp;|&nbsp; scores source: {safe(data['scores_source'])}", body)]

    el.append(Paragraph("Competency profile by National Occupational Standard", h2))
    rows = [["NOS", "Weight", "Score", "Pass mark", "Result"]]
    for n in p["nos"]:
        res = "Pass" if n["passed"] else ("Critical fail" if n["critical_failure"] else ("Incomplete" if not n["complete"] else "Below"))
        rows.append([Paragraph(safe(n["title"]), cell), f"{int(n['weight'] * 100)}%", f"{n['score_pct']}%",
                     f"{n['pass_threshold_pct']}%", res])
    t = Table(rows, colWidths=[78 * mm, 20 * mm, 22 * mm, 24 * mm, 32 * mm], repeatRows=1)
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), TEAL), ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                           ("FONTSIZE", (0, 0), (-1, -1), 8.8), ("GRID", (0, 0), (-1, -1), 0.25, colors.lightgrey),
                           ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]))
    el.append(t)

    el.append(Paragraph("Criterion scores", h2))
    rows = [["Criterion", "Assessor", "AI hint"]]
    for n in p["nos"]:
        for c in n["criteria"]:
            ai = data["ai_scores"].get(c["criterion_id"])
            rows.append([Paragraph(safe(c["text"] + (" [critical]" if c["critical"] else "")), cell),
                         SCORE_LABEL.get(c["score"], "Not scored"), "-" if ai is None else str(ai)])
    t = Table(rows, colWidths=[110 * mm, 40 * mm, 26 * mm], repeatRows=1)
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), TEAL), ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                           ("FONTSIZE", (0, 0), (-1, -1), 8.6), ("GRID", (0, 0), (-1, -1), 0.25, colors.lightgrey),
                           ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]))
    el.append(t)

    if p["gaps"]:
        el.append(Paragraph("Gaps to address", h2))
        for g in p["gaps"][:12]:
            el.append(Paragraph("- " + safe(g), body))

    el.append(Paragraph("Assessor sign-off", h2))
    so = data.get("sign_off")
    if so:
        el.append(Paragraph(f"Decision: <b>{safe(so['decision'])}</b> by {safe(so['assessor'])} on {safe(so['created_at'])}."
                            + (" Overrode the system recommendation." if so["overridden"] else ""), body))
        if so.get("reasoning"):
            el.append(Paragraph("Reasoning: " + safe(so["reasoning"]), body))
    else:
        el.append(Paragraph("Not yet signed off.", body))
    el += [Spacer(1, 18), Paragraph("Assessor signature: ______________________ &nbsp;&nbsp; Date: ______________", body),
           Spacer(1, 10), Paragraph("Scores are 0-3 on a standard anchored rubric (0 not demonstrated, 1 partial, 2 competent "
                                    "with minor guidance, 3 independent to standard). AI hints come from a rule-based indicator "
                                    "matcher (optionally an LLM) and never replace assessor judgement.", small)]
    doc.build(el)
    return buf.getvalue()
