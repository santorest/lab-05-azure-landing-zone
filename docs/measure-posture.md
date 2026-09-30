# Measuring posture (Defender for Cloud secure score)

> **No secure score was measured for this lab**: it was never deployed. This is the procedure for recording
> a before/after comparison if you deploy it.

Defender for Cloud's **foundational CSPM** is free and on by default for every subscription. It computes a
**secure score** from its recommendations (the Microsoft cloud security benchmark).

## Before

1. In a fresh subscription, before applying the landing zone, wait until Defender for Cloud has assessed it
   (up to 24 hours for a new subscription).
2. Record the score and the recommendation list:
   ```bash
   az security secure-scores list --query "[].{name:displayName, current:score.current, max:score.max, pct:score.percentage}" -o table
   az security assessment list --query "[?status.code=='Unhealthy'].{rec:displayName, severity:metadata.severity}" -o table > before.txt
   ```
   Note the date and time.

## After

1. Apply the landing zone and wait for the next assessment cycle (again up to 24 hours).
2. Run the same two commands into `after.txt`.
3. Compare: which recommendations disappeared (e.g. storage public access, Key Vault network access, missing
   diagnostic settings) and which new ones appeared (e.g. customer-managed keys, which this design accepts;
   see `security/EXCEPTIONS.md`).

## What to publish

Only numbers you recorded, with their date: score before, score after, and the recommendation changes. If
the score moves for reasons unrelated to the landing zone (new resources, benchmark updates), say so.
