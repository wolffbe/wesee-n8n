# Examples

Test fixtures for exercising the workflow end to end. Both companies are **fictional** and the decks were generated for this purpose — they are not real pitches and the figures in them are invented.

Each example is an email body plus the deck that goes with it. To use one, send the email to the monitored `deals@`/`info@` mailbox with the PDF attached, then run the `wesee` workflow.

| Example | Sector | Stage | Raising | ARR |
| --- | --- | --- | --- | --- |
| [Vitera Health](ViteraHealth_email.txt) ([deck](ViteraHealth_PitchDeck.pdf)) | Healthtech — remote monitoring for chronic heart failure | Seed | EUR 450K | EUR 180K |
| [NeuralNex](NeuralNex_email.txt) ([deck](NeuralNex_PitchDeck.pdf)) | Enterprise AI workflow automation | Series A | USD 15M | USD 8M |

## What each one is for

**Vitera Health — the positive case.** It fits the default thesis in `config.thesis` (early-stage healthtech, ticket size 100k–500k): right sector, right stage, and a raise inside the ticket range. Use it to check that classification passes, that both extraction and the judgment columns produce sensible values, that the attachment lands in OneDrive, and that a row appears in Notion with the company name as the page title.

The deck deliberately contains material for the judgment columns: CE Class IIa marking and DiGA reimbursement (regulatory position for `Moat`), a 212-patient pilot with a 31% readmission reduction (`Traction`), 74% gross margin and 14-month CAC payback, EUR 38K/month burn with 16 months of runway, and a founding team combining a cardiologist with an ML lead.

**NeuralNex — the negative case.** It should be *rejected* on thesis fit: it is enterprise AI automation rather than healthtech, Series A rather than early stage, and raising USD 15M against a 100k–500k ticket. Depending on how strictly the classifier reads `config.thesis`, it may be dropped at classification; if it does get through, `Thesis Fit` and `Investment Advice` should both come back negative.

It also carries deliberate red flags for the `Risks` column — a USD 150B top-down TAM, and an advisor list of well-known industry figures presented as endorsement.

## Notes

- Both PDFs have a real text layer, so n8n's `extractFromFile` reads them directly; no OCR is involved.
- The Vitera deck writes `EUR` rather than `€` so nothing depends on glyph encoding surviving extraction.
- The email bodies are plain, non-forwarded messages, so they take the normal path through `wesee - parse email` rather than the forwarding branch.
- For repeated runs set `config.cache.add` to `false` and `config.cache.reset` to `true`, so the same email is not skipped as a duplicate. Each run creates a new Notion row.
