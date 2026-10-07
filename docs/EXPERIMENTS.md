# Paywall experiment: annual-default against weekly-default

Ready to switch on once there's traffic. Nothing in the app changes to run it.

## How the app reads it

The paywall starts with one plan selected. It reads that from the current RevenueCat offering's
metadata (`PaywallExperiment.defaultPlan`):

```json
{ "default_plan": "weekly" }
```

No metadata, or anything other than `annual`, `weekly` or `lifetime`, means annual.

## Set-up in RevenueCat

1. **Products** (App Store Connect, then imported into RevenueCat), all attached to the
   `premium` entitlement:
   - annual subscription with a 7-day free trial (introductory offer: free trial, 1 week)
   - weekly subscription, no trial (the anchor)
   - lifetime: a non-consumable
2. **Offering `default`**: packages `$rc_annual`, `$rc_weekly`, `$rc_lifetime`, no metadata (or
   `{"default_plan": "annual"}`). Make it the current offering.
3. **Offering `weekly_default`**: the same three packages, metadata
   `{"default_plan": "weekly"}`.
4. **Experiment** (Experiments → New): control `default`, treatment `weekly_default`, 50/50,
   new customers only. Leave it paused until there are enough installs to read it (RevenueCat
   shows the sample size it needs).

## What to watch

- Trial start rate and initial conversion (RevenueCat reports both per variant).
- Realised revenue per customer at 30 and 90 days, not just conversion: weekly-default may convert
  more and earn less.
- Refunds and cancellations in the first week.

Call it on revenue per customer, not on the first conversion.
