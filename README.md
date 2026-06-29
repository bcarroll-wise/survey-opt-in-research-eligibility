# Survey Opt-In & Research Eligibility Analysis

An investigation into why research outreach reaches so few Wise customers, despite opt-out rates that should leave a large addressable pool.

## Headline

**Wise customers are far more willing to be contacted for research than Braze's filtering implies. The losses come from notification-page design, an inadvertent global experimentation exclusion, and a 30-day cooldown that lumps research in with marketing — together these can remove the large majority of opted-in users from any given study.**

## Key findings

| Stage | Impact on reachable pool | Intent signal? |
|-------|--------------------------|----------------|
| Notification opt-outs | At most ~20% genuinely opt out of research | Mixed — 25–70% of opt-outs look unintentional |
| Notifications page design | Up to ~70% of research opt-outs coincide with email/all-notification purges | Weak — anti-email, not anti-feedback |
| Global Experimentation Framework | ~30% of opted-in users excluded on average, up to ~90% in some segments | None — filtered by default, outside the framework's purpose; now resolved |
| 30-day outreach cooldown | ~35–50% ineligible on a given day from any prior email; only 1–5% from prior research | Cooldown is sound; the grouping is the issue |

## Method

- **Data**: 1,000,000-user sample (of ~4M) across GBR, USA, CAN, FRA, DEU, AUS, from `NOTIFICATIONS.USER_PREFERENCES`, cross-checked against `RPT_CRM` preference/opt-out tables; comms recency from `RPT_CRM.INT_COMMS_TRUNCATED`.
- **Approach**: Opt-out rates per notification channel (with finite population correction), opt-out co-occurrence correlations, global-group assignment splits, and a daily time-series of cooldown-driven research ineligibility over the trailing 90 days.
- **Controls**: Country breakdowns; research vs non-research comms separated via Braze `PARENT_TAGS`; deterministic hashing for the cooldown cohort sample.

## Important caveats

1. The cooldown analysis models a simple "any email in prior 30 days" rule; Wise's real Braze frequency rules may differ by channel/campaign type, so the top line is an upper bound on email-driven ineligibility.
2. Per-country population sizes are estimated by scaling the sample share, so country-level confidence intervals are approximate.
3. "Unintentional" opt-out intent (25–70%) is inferred from co-occurrence patterns, not directly observed — confirming it requires follow-up research.

## Implication

Most of the lost research reach is a measurement/configuration artefact, not genuine unwillingness to give feedback. Separating research outreach from marketing (in the settings page, the experimentation framework, and the cooldown grouping) could reclaim a large share of the addressable pool.

## Repo layout

| File | Purpose |
|------|---------|
| `analysis.ipynb` | Full analysis notebook with all charts |
| `Visualisations/` | Exported chart images + notifications screen screenshot |
| `notification flags.sql` | Pulls the per-user notification preference flags |
| `notif prefs compared to crm.sql` | Compares notification prefs vs CRM logged preferences |
| `research eligibility erosion.sql` | Daily cooldown-driven research ineligibility time series |
| `requirements.txt` | Python dependencies |

## Run

```bash
pip install -r requirements.txt
jupyter notebook "analysis.ipynb"
```

## Notes

- The notebook imports a local `wise_colours` module (Wise brand palette) that is not included here; charts will need it or a substitute to re-render.
- Source CSVs are **not** committed — they contain user IDs and raw preference data. Regenerate them from the SQL files against Snowflake.
- SQL targets Wise Snowflake schemas (`NOTIFICATIONS`, `RPT_CRM`, `REPORTS`) and requires appropriate access.
