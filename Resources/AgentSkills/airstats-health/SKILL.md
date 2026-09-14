---
name: airstats-health
description: Use when the user asks about their personal Fitbit or Google wearable health, sleep, activity, recovery, vitals, or recent trends available through Air Stats. Do not use for generic health questions that do not need the user's wearable data.
---

# Air Stats health

Use the Air Stats MCP tools to ground answers in the user's current, read-only wearable data.

- Call `get_health_summary` first. Call `get_health_metric` only when exact underlying points help answer the question.
- State the relevant measurement dates or times and whether the data may be stale. Wearable readings appear only after the tracker syncs to the phone and Google; heart rate is not a live Bluetooth stream.
- Distinguish a missing value, a denied or failed source, and a real zero. Mention meaningful coverage gaps before drawing a conclusion.
- Compare recent values with the user's own available trend when useful. Do not invent clinical thresholds, diagnoses, causes, or treatment advice from wearable data.
- Treat `durationEfficiencyPercent` as a duration ratio, not Fitbit Sleep Score. Fitbit Sleep Score and Daily Readiness Score are unavailable through the Google Health API.
- The reconciled `google-wearables` stream can include compatible Fitbit and Pixel devices on the same account; do not claim a reading came from one particular device unless the data establishes that.
- If the user reports urgent symptoms or asks for a clinical decision, clearly separate the wearable observation from medical assessment and direct them to appropriate professional or emergency care.
- Never request, reveal, or persist OAuth credentials. Do not save raw health output to project files unless the user explicitly asks.

For a broad question such as “How am I doing?”, give a concise summary of the strongest evidence-backed observations, note data freshness and limitations, and suggest a useful follow-up question when the data supports one.
