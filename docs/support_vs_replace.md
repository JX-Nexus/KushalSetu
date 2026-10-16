# Where the tool supports and where the assessor decides

| Step | AI / tool does | Assessor / human does |
|---|---|---|
| Self-declaration → qualification pack | Ranks closest packs (TF-IDF over NOS vocabulary; EN/HI/MR/Hinglish, typo tolerant) with matched terms and a confidence band | Worker confirms the pack; assessor sees the mapping and can see it was low confidence |
| Practical checklist | Generated from the pack's NOS/criteria; evidence type (photo/video) requested per criterion | Decides if the evidence is adequate; can request more evidence |
| Score suggestion | Rule-based indicator matcher gives a 0–3 *hint* with matched / missing indicators; a written answer alone is capped below level 3 where practical evidence is required; optional LLM adds a rationale and a follow-up question; optional photo description | **Every score is entered by the assessor.** AI hints can be hidden (blind mode) |
| Profile + recommendation | Computes NOS scores (weights, pass marks, safety-critical criteria must be ≥ 2) and a *recommendation* | Reviews and signs off, or overrides with written reasoning |
| Certification | **Nothing.** The tool never issues a certificate | Final decision, logged in the audit table |
| Consistency | Computes weighted kappa / ICC between assessors, assisted vs blind, and AI vs assessor | Provides the double-scored data |

Guard-rails in code: scores come only from assessors (`assessor_scores`); sign-off requires every criterion scored;
overriding the recommendation or requesting more evidence requires reasoning; the LLM can never change a score;
all sign-offs and overrides are written to `audit_log`.
