# Result: the NFL model gauntlet (run 2026-11-04)

**Status: valid.**
- **Controls:** every one passed.
- **Reproducibility:** two independent runs wrote byte-identical outputs, result sha256 `4d85d98cdb0d0db2a1163365fc8fb3ef70c601fafa4408894b466ac7ef591d14`.
- **Pre-registration:** the plan was committed before any score (`5cca2d7`, PLAN.md sha256 `bf5b34e6…`), and nothing departed from it.

**Headline: none of the 20 candidates beats the no-vig close on 2018–2022, or adds to it.**
- **Families alone:** all ten lose to the market by 4–15% Brier skill, and every interval lies wholly on the losing side.
- **Stacks:** all ten come within +0.0001 to +0.0005 Brier of the market alone, with every interval spanning zero.
- **What it does not mean:** this is a wider null than games v1's, not proof that no edge exists. The test needs a candidate about 1.9% better than the close to pass after Holm (see power).

## What was searched

- **Families:** ten, F1–F10 in PLAN.md:
  - Elo, QB-adjusted Elo, the EPA ridge;
  - margin ratings with three home-field treatments;
  - Poisson scores, Kalman dynamic ratings;
  - a drive-by-drive simulator (the reading of "RoboBot sim");
  - gradient-boosted trees.
- **Stacks:** one market stack per family, logit P = a + b·logit(close) + c·(logit P_F − logit close), refitted before every week.
- **Selection:** 2012–2017, walk-forward. **Scoring:** once, on 2018–2022, 1,365 games with a no-vig close and a result. Seasons 2023–2025 were not read.

**Power.**
- **Precision:** on six selection seasons the week-block bootstrap SE of a Brier difference is 0.0013.
- **The bar:** a one-sided 5% test after Holm over 20 candidates needs a difference of about −0.0036 on six seasons. On the five scored seasons that is 1.9% of the market's Brier.
- **So:** an edge smaller than that would not show here.

## Selection (2012–2017, walk-forward log loss; `out/selection.csv`)

| Family | Selected setting | Log loss |
|---|---|---|
| F8 Kalman ratings | process SD 0.5 pts/week, carry 0.75 | 0.62123 |
| F1 Elo | K 20, home 55, regression 0.45 | 0.62222 |
| F4 margin ratings | half-life 32 weeks | 0.62581 |
| F10 gradient boosting | depth 2, 100 rounds | 0.62684 |
| F5 ratings, strength-free team home field | half-life 32, shrink 16 | 0.62905 |
| F3 EPA ridge | half-life 16, λ 10 | 0.62931 |
| F2 QB-adjusted Elo | weight 0.5, QB half-life 16 | 0.63113 |
| F6 ratings, the engine's team home field | half-life 32 | 0.63612 |
| F9 drive simulator | half-life 32 | 0.63645 |
| F7 Poisson scores | half-life 32 | 0.69840 |

Several settings sit on a grid edge: the longest half-life (F4–F7, F9), F2's smallest QB weight and F5's strongest shrinkage. A wider grid might help those families, but under the plan it would have to be a new run.

## Scored window (2018–2022; `out/results.csv`)

Brier difference = candidate − market (negative is better), with week-block bootstrap 95% intervals. Skill = 1 − Brier / market Brier. Margin MAE is points against the actual margin; the market's is the closing spread's.

| Candidate | Brier | Difference | 95% interval | Skill | Calibration slope | Margin MAE |
|---|---|---|---|---|---|---|
| Market (no-vig close) | 0.2111 | — | — | — | 1.05 | 9.88 |
| S[F3] EPA ridge stack | 0.2113 | +0.0001 | −0.0004 to +0.0007 | −0.07% | 0.97 | |
| S[F10] boosting stack | 0.2113 | +0.0001 | −0.0005 to +0.0008 | −0.07% | 0.97 | |
| S[F5] | 0.2113 | +0.0002 | −0.0005 to +0.0010 | −0.11% | 0.97 | |
| S[F9] drive-simulator stack | 0.2114 | +0.0002 | −0.0007 to +0.0012 | −0.11% | 0.97 | |
| S[F8] | 0.2114 | +0.0002 | −0.0004 to +0.0009 | −0.12% | 0.97 | |
| S[F4] | 0.2114 | +0.0003 | −0.0006 to +0.0012 | −0.15% | 0.97 | |
| S[F2] | 0.2115 | +0.0003 | −0.0005 to +0.0012 | −0.16% | 0.97 | |
| S[F7] | 0.2115 | +0.0004 | −0.0005 to +0.0012 | −0.18% | 0.97 | |
| S[F6] | 0.2115 | +0.0004 | −0.0005 to +0.0013 | −0.19% | 0.97 | |
| S[F1] | 0.2116 | +0.0005 | −0.0003 to +0.0012 | −0.22% | 0.97 | |
| F3 EPA ridge | 0.2196 | +0.0084 | +0.0041 to +0.0129 | −4.00% | 0.99 | |
| F10 gradient boosting | 0.2212 | +0.0100 | +0.0054 to +0.0144 | −4.75% | 1.01 | |
| F1 Elo | 0.2238 | +0.0127 | +0.0083 to +0.0171 | −5.99% | 1.01 | |
| F8 Kalman ratings | 0.2241 | +0.0130 | +0.0082 to +0.0177 | −6.14% | 0.95 | 10.33 |
| F4 margin ratings | 0.2250 | +0.0139 | +0.0081 to +0.0198 | −6.59% | 0.75 | 10.37 |
| F5 strength-free team home field | 0.2262 | +0.0151 | +0.0091 to +0.0210 | −7.14% | 0.73 | 10.40 |
| F2 QB-adjusted Elo | 0.2267 | +0.0156 | +0.0103 to +0.0210 | −7.39% | 0.73 | |
| F9 drive simulator | 0.2268 | +0.0156 | +0.0100 to +0.0212 | −7.41% | 1.52 | 10.22 |
| F6 the engine's team home field | 0.2299 | +0.0188 | +0.0121 to +0.0254 | −8.88% | 0.62 | 10.62 |
| F7 Poisson scores | 0.2429 | +0.0318 | +0.0231 to +0.0406 | −15.06% | 0.37 | 10.40 |

Every Holm-adjusted p is 1.000: no candidate is better than the market in a one-sided test.

## Controls (`out/controls.csv`, `out/controls_scored.csv`)

| Control | Result |
|---|---|
| K1a: the leaked margin is rejected by the as-of assertion | passed |
| K1b: a stack given the leak passes (Brier −0.109, interval −0.121 to −0.098) | passed: the test detects a real signal |
| K2: a noisy copy of the market does not pass (+0.0012) | passed |
| K3: Elo and ratings trained on shuffled scores do not pass (+0.048, +0.046) | passed |
| K4: no family shows implausible skill | passed |
| K5: two runs give identical outputs | passed |

## Findings

1. **Nothing here beats the close, or adds to it.** That holds for the ten families, including the drive simulator, gradient boosting and the dynamic ratings, and for every market stack.
   - The best single families are the EPA ridge (−4.0%) and the boosted trees (−4.75%).
   - The selection window's best, the Kalman ratings, came fourth in scoring.
2. **The engine's home-field estimator costs accuracy** (`out/home_field_compare.csv`, the planned comparison, paired, 1,365 games):

   | Comparison | Brier difference | 95% interval |
   |---|---|---|
   | F6 − F4 (league home field) | +0.0048 | +0.0025 to +0.0072 |
   | F6 − F5 (strength-free) | +0.0037 | +0.0013 to +0.0061 |
   | F5 − F4 | +0.0012 | +0.0003 to +0.0020 |

   - **The pattern:** team-specific home field did not pay even with the strength confound removed, and a single league value was best.
   - **Calibration:** the engine's estimator makes the ratings more overconfident (slope 0.62 against 0.75).
   - **The engine change:** admit the league home field in place of `team_hfa_table()`'s mean home margin, through the walk-forward term-admission backtest (M22). These figures are evidence for that backtest, not a substitute for it.
3. **The drive simulator** (F9, the "RoboBot sim" reading):
   - its median margins come closest of all the models to the result (MAE 10.22 against the spread's 9.88);
   - its win probabilities are too timid (slope 1.52): shrinking each team's drive rates toward the league flattens matchups;
   - it adds nothing in a stack.
4. **Poisson scores are badly overconfident** (slope 0.37). A Poisson score's variance equals its mean, so the implied margin SD is about 6.7 points against the NFL's 14.2. Tie probabilities run about 4% against the real 0.3%.
5. **The QB adjustment hurt Elo** at the selected scale (−7.4% against −6.0%). The grid's smallest weight was chosen, which suggests the scale (25 Elo points per point × 35 dropbacks × EPA per dropback) is too large. A smaller weight is untested here.

## What follows

- **No confirmation protocol:** nothing passed.
- **The home-field result** goes to the engine's term-admission work (M22). The production engine keeps its estimator until that backtest admits a change.
- **Next searches** would have to change the question, not only the model:
  - prices before the close (the pre-close protocol is running prospectively);
  - markets other than the moneyline (spreads, totals, props);
  - information the close may lack, such as late injury news.
  - Each needs its own pre-registration.
