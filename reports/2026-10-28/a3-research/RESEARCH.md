# A3 research: the S4 null, the joint test, the cluster unit and late schedule changes

2026-10-28. Requested by the owner the same day: research a new approach to the label shuffle; research the inherited robust joint test and how games are grouped, and recommend one; test whether late schedule changes matter; admit only significant variables; check bias, variance and the trade-offs.

**Scope.** This work is exploratory, on v2's Tune window: 2018–2022, 1,372 games, anchored on the close.
- The loaders refuse 2025.
- Confirm (2023–2024) scores no model here.
- The one look at 2023–2024 is the opener-to-close movement in §4, which compares market prices only.

**Numbers.** Every number below is in `summary.txt` or in the log named beside it. `scripts/research-summary.R` writes `summary.txt` from the result files in this folder.

## Recommendations

| Question | Recommendation | Evidence |
|---|---|---|
| The S4 null | **The anchor null as the gating control:** redraw y from the anchor (consistency resampling). Report the permuted-x null beside it. Judge each by S3's own claim rule, not by "every interval includes 0". Needs the owner's amendment of spec §4. | The spec's null claimed skill in 5 of 5 replicates (6.6 intervals wholly above 0 per replicate). The two researched nulls claimed nothing in 5 of 5. |
| The joint test | **`p_joint = max(p_test, p_joint_wild)`.** `p_joint_wild` is a restricted wild cluster score bootstrap with diagonal studentization. Keep `p_wald_robust` only for v2 fidelity, and never cite it. | At a nominal 5%, the cluster-robust Wald rejects 0.30–0.69 of the time under a true null. The diagonal score bootstrap rejects 0.041–0.059, inside the Monte Carlo band of 0.036–0.064. |
| The cluster unit | **Keep the season-week.** | The ICC is 0.0000 at every unit, except 0.0006 for totals by team-season. The median design effect is 1.004–1.064 at every unit. |
| Late schedule changes | **No adjustment and no feature.** | 51 of 1,372 Tune games (3.7%) changed. No test against the close is significant (p 0.33–0.81). Dropping them changes 0 of 108 S1 verdicts. |
| Admission | **A variable enters only if it passes S0, S1, S3 and S4 on Tune, then Confirm under G3.** Against the close, none of the 36 does; the A3b run gives S3. | §5 |

## 1. The S4 null

### Why the spec's control fails

S3 scores `logit(p) = lp_anchor + b·x_c` against the anchor alone. The spec's control permutes y within week and requires every S3 interval to include 0. That control fails by construction:
- **Shuffling breaks the anchor.** Shuffled labels no longer follow the anchor, so the offset becomes noise. A feature that tracks the anchor can then cancel part of it (b < 0) and beat it.
- **The 2026-10-27 diagnostic** (B = 2,000, `s4-null-diagnostic.csv`) found 7 of 36 intervals wholly above 0. The largest skills were `lp_anchor` 0.100, `home_dog` 0.058 and `d_e1` 0.036. Skill correlated 0.954 with |cor(x, anchor)|.
- **The criterion fails too.** "Every interval includes 0" fails on any null where some intervals lie wholly below 0, and an interval below 0 is the expected cost of fitting noise. Over five replicates:
  - the anchor null failed it 5 times, with a mean of 2.4 intervals below 0;
  - the permuted-x null failed it 4 times, with a mean of 3.4 below 0;
  - yet neither claimed any skill.

### The candidates

| Null | What it keeps | What it assumes | Source |
|---|---|---|---|
| y permuted within week (the spec's) | Each week's win count | That the anchor carries no information, which is false | design 2026-10-20 §4 |
| **y drawn from the anchor**, y* ~ Bernoulli(p_anchor) | x, the anchor, and their dependence | That the anchor is calibrated: S3's model with b = 0 | Bröcker and Smith (2007), consistency resampling; Davison and Hinkley (1997, ch. 4), parametric bootstrap tests |
| x permuted within week | y with the anchor; each week's x values | That x is independent of y and of the anchor within the week, a stronger null | Fisher's randomization; the within-block permutation |
| x drawn or permuted given the anchor | y, and x's link to the anchor | A model of each feature given the anchor (36 of them) | Candès et al. (2018), the CRT; Berrett et al. (2020), the CPT |

**Why the anchor null.**
- It is the exact null of the model S3 fits.
- It conditions on the anchor through the one model S3 already uses, not 36 new ones.
- It keeps every feature's dependence on the anchor intact.

**Its assumption.** It needs the anchor to be calibrated. If the anchor were miscalibrated, a feature that tracks it could earn real out-of-sample skill by recalibrating it, and this null would treat that as false skill. The A3b run checks the assumption twice, on the same Tune games:
- the close's calibration slope (S5);
- `lp_anchor`'s own S3 skill.

**The permuted-x null** needs no model at all. It is reported as a second opinion.

### The criterion

A null passes when S3's claim rule claims no feature: the skill CI lies above 0 and the BH-adjusted DM-HLN p is below 0.05.
- Under the global null, the false discovery rate equals the family-wise error rate. So BH at 0.05 (Benjamini and Hochberg, 1995; valid for independent or positively dependent tests, as these paired scores on the same games are) makes the control fail at most 5% of the time on a sound pipeline.
- A leak or a scoring bug makes many features look skilled, and the control fails.

### Results

Five replicates per null, 36 features each, B = 1,000, on the close-anchored Tune table (`s4_nulls.csv`, `scripts/a3-research.R s4`):

| Null | Intervals wholly above 0 per replicate (mean, max) | Wholly below 0 (mean) | Replicates with a claim | Claims in all |
|---|---|---|---|---|
| y within week (spec) | 6.6, 9 | 0.4 | 5 of 5 | 20 |
| x permuted within week | 0.0, 0 | 3.4 | 0 of 5 | 0 |
| **y drawn from the anchor** | 0.6, 2 | 2.4 | 0 of 5 | 0 |

**Power** (`s4_power.csv`). An effect was planted on `rest_diff`, standardized on Tune, with y redrawn as Bernoulli(plogis(lp_anchor + β·z)), 5 replicates each:

| Planted β per SD | Detected by S3 | Mean skill |
|---|---|---|
| 0.05 | 1 of 5 | 0.00153 |
| 0.10 | 1 of 5 | 0.00244 |
| 0.20 | 3 of 5 | 0.00782 |

S3 on Tune reliably sees only effects of about 0.2 log-odds per SD or more. "No incremental skill" is therefore no evidence against smaller effects. It is the honest reading of an underpowered window, and it is why the Tune window grows (track H) before the opener tests mean much.

## 2. The joint test

### The problem

v2's joint test of a feature set is a cluster-robust (CR) Wald χ²(k). On Tune, k is 29–34 coefficients over G = 107 week clusters.
- **It over-rejects.** CR Wald tests over-reject when the number of restrictions is large relative to the number of clusters (Pustejovsky and Tipton, 2018; MacKinnon, Nielsen and Webb, 2023).
- **It can be undefined.** With an intercept, the slopes' cluster-robust covariance has rank at most G − 1, so it is singular when k ≥ G − 1. One season has G = 22, so v2's 29-feature set cannot be tested on it, and the current code stops with an error.

### The candidates

| Test | Notes |
|---|---|
| The LR test (outcome) or F test (spread, total) | Model-based; ignores clustering |
| The CR Wald χ²(k), and the same over k against F(k, G − 1) | v2's test; HC0 week-clustered covariance |
| The restricted wild cluster score bootstrap, full studentization `S'V⁻¹S` | Kline and Santos (2012); Cameron, Gelbach and Miller (2008); Roodman et al. (2019). The scores are summed by cluster at the null fit and flipped with Rademacher weights. Needs G > k. |
| The same, **diagonal studentization** `Σ S_j² / V_jj` | Defined for any k. With Rademacher weights the bootstrap variance equals V, so no refit is needed. |

### Design

`scripts/a3-research.R joint` (outcome) and `joint_linear` (spread, total).
- **Draws:** 1,000 null draws per setting, each with 999 Rademacher draws.
- **Outcome family:** y drawn from the anchor with a season-week effect of SD 0, 0.1 or 0.2 on the logit scale. The estimated week SD on Tune is 0.000 (`logs-joint.txt`), so the fixed SDs test robustness.
- **Spread and total families:** r drawn as the mean, plus a week effect of SD 0, 1 or 2 points, plus a resampled centred residual.

### Null size at a nominal 5%

| Test | Outcome, 107 clusters | Spread, 107 clusters | Total, 107 clusters | Outcome, one season (22 clusters, k = 29) |
|---|---|---|---|---|
| LR / F | 0.053–0.073 | 0.051–0.061 | 0.041–0.057 | 0.116 |
| CR Wald χ² | 0.399–0.538 | 0.512–0.658 | 0.516–0.690 | undefined |
| CR Wald F | 0.304–0.438 | 0.433–0.574 | 0.420–0.582 | undefined |
| Score bootstrap, full | 0.049–0.062 | 0.040–0.061 | 0.038–0.047 | undefined |
| **Score bootstrap, diagonal** | **0.041–0.049** | **0.045–0.059** | **0.041–0.046** | **0.054** |

The Monte Carlo 95% band for a true size of 0.05 with 1,000 draws is 0.036–0.064.

**Recommendation.**
- The p of record is `max(p_test, p_joint_wild)`, where `p_joint_wild` is the diagonal score bootstrap. This mirrors S1's per-feature rule, `p = max(p_model, p_robust)`.
- The diagonal bootstrap holds its size in every setting, including the one season where nothing else is defined.
- The LR alone over-rejects once games share a week effect (0.067–0.073 at a week SD of 0.1–0.2) and on one season (0.116).
- The maximum's size is at most the smaller of the two.
- `p_wald_robust` stays in the tables as v2 fidelity, labelled not size-controlled. Dropping it is the owner's decision.

## 3. The cluster unit

**The candidates:**
- the season-week (the current `wk`);
- the week of season, pooled across seasons;
- the game day;
- the team-season (each game counted once per team, with its sign);
- two-way: week and home team.

**ICC.** One-way ANOVA ICC of the residuals against the close (`cluster_icc.csv`):
- e_out = y − p_anchor;
- the ATS residual;
- the total residual.

| Unit (groups) | ICC, e_out | ICC, ATS | ICC, total | F-test p (range) |
|---|---|---|---|---|
| Season-week (107) | 0.0000 | 0.0000 | 0.0000 | 0.657–0.864 |
| Week of season (22) | 0.0000 | 0.0000 | 0.0000 | 0.595–0.935 |
| Game day (292) | 0.0000 | 0.0000 | 0.0000 | 0.545–0.840 |
| Team-season (160) | 0.0000 | 0.0000 | 0.0006 | 0.454–0.959 |

**Design effects.** The variance of each S1 coefficient clustered at a unit, over HC0, for 30 features (`cluster_design_effects.csv`). The median is 1.055 for the season-week, 1.004 for the week of season, 1.044 for the game day, and 1.064 for two-way.

**Recommendation: keep the season-week.**
- Residuals against the close show no within-cluster correlation at any unit, so the unit barely changes inference.
- In the design-based view (Abadie et al., 2023), clustering matters when the correlation is there, and it is not.
- The season-week nests the game day. It matches the weekly refit and the weekly decision, and it gives 107 clusters on Tune, well above the 30 at which the wild bootstrap takes over.
- Pooling by week of season would mix five seasons in each cluster, and one season would have only 22 clusters.

MacKinnon, Nielsen and Webb (2023) advise checking the level, and these design effects do that: a finer unit (game day) or a coarser one (week of season, two-way) moves the median by at most 0.051.

## 4. Late schedule changes

### Data

Each "<season> NFL season" Wikipedia article has a "Scheduling changes" section. It was read for 2018–2024 through the keyless MediaWiki API (`scripts/flex-fetch.mjs`, with at most one request per 1.2 s, a truthful user agent, a 20 s timeout and a stop on 403 or 429). The fixed revisions are in `data/wikipedia_revisions.json`.
- **Rows:** each bullet is one row per changed game (`data/flex-games.csv`, 77 rows), matched to nflverse games by franchise code. By kind: 38 primetime, 14 date, 14 other, 6 network only, 4 day, 1 venue. Every season has rows.
- **Lateness by rule.** Citation access dates are not announcement dates, and some fall after kickoff. So "late" is defined by rule: a date or venue change, or any change in weeks 17–18.

### The rules

- **Sunday night** (the NFL's procedures, in the text that holds the 2022 rules):
  - flexible in weeks 5–17 since 2014;
  - each change is announced no later than the Tuesday 12 days before the game;
  - week 18's two Saturday games and its Sunday night game are announced no later than 6 days before.
- **Monday night:** flexible in weeks 12–17 since 2023 (NBC Sports' explainer of the 2024 rules).
- **Thursday night:** flexible since 2023, with at least 28 days' notice to the teams (the Rams' 2023 release).

**What that means at each decision.**
- At the close, which is this run's decision, every flex is public.
- At the opener, a weeks 5–17 flex is public, because 12 days precede the game week's lines.
- Week 18's primetime slots are the exception: 6 days' notice can follow the opener. Those games fall under "late" below, by the weeks 17–18 rule.
- The other true late changes are date and venue changes, such as the 2020 COVID reschedules.

### Tests against the close

`scripts/a3-research.R late` (`late_tests.csv`):

| Indicator | Tune games | Moneyline log-odds (LR p, robust p) | ATS points (robust p) |
|---|---|---|---|
| Changed | 51 (3.7%) | +0.136 (0.660, 0.586) | +1.12 (0.525) |
| Late | 19 (1.4%) | +0.386 (0.450, 0.339) | +0.82 (0.812) |
| A primetime change | 27 (2.0%) | −0.099 (0.812, 0.757) | +2.15 (0.326) |

- **S1 with the changed games out** (`late_s1_sensitivity.csv`): 0 of 108 verdicts change. The smallest q without them is 0.276 (spread, `abs_tz_away`).
- **Opener-to-close movement, 2023–2024** (`late_movement.csv`, `scripts/late-movement.R`, ESPN BET from D1's archive; permutation p):
  - changed games moved no more than the rest: 0.150 against 0.166 on the logit scale (p 0.662), and 0.971 against 1.208 spread points (p 0.476);
  - the 3 late games: p 0.906 and 0.519.

**Recommendation: no adjustment and no feature.**
- A late change is rare, and it predicts nothing against the close.
- It does not alter the screen.
- `primetime` keeps its `schedule` class at the close and at weeks 5–17 openers, since a flex is public by then.
- The residual known-at risk is limited to the 19 late games: their rest and travel values, and week 18's primetime flag at the opener. They are left in, because dropping them changes nothing.
- The opener screen (A4) should test this again on its own window.

## 5. Admission: only significant variables

A variable enters a model only if all of these hold:

1. **S0.** It is known at the decision (the registry's `known_at`).
2. **S1.** q < 0.05 in its family (BH within the family).
3. **S3.** Its skill CI lies above 0, with a BH-adjusted DM-HLN p below 0.05, on Tune.
4. **S4.** The run is complete: no gating control failed.
5. **Confirm.** The same holds on 2023–2024 under G3's signed protocol. Confirm is never scored here.

Significance is not manufactured. A variable that fails is excluded, even if only the market remains. Against the close on Tune, S3 claims none of v2's 36 features (the A3b run's `s3_skill.csv`), so the close-anchored model is the market alone. The opener screen (A4, from D1's archive) is next, and the power above says how little a null there can rule out.

**Bias and variance.** S5 in the A3b run (`reports/2026-10-28/vvf-a3b-close/`) reports the bias–variance evidence:
- the learning curve and the fit gap of the anchor-plus-every-feature logit against the anchor;
- the C2 half-life validation curve with the one-SE rule;
- the calibration slopes;
- the Murphy decomposition;
- the bias and variance of the margin and total errors.

## 6. Limits

- **One window.** Every result is on one window, Tune 2018–2022.
- **Replicates.** The S4 study has 5 replicates per null at B = 1,000. A rare false claim would need more replicates to see. The criterion's level is set by BH, not by these replicates.
- **The size study's DGPs.** It assumes the outcome follows the anchor plus a week effect. A different dependence (team-season, two-way) could change the sizes. The ICCs above say the data show none.
- **Wikipedia's coverage.** The late-change data are only what Wikipedia lists, and the announcement dates are unknown. A change missing from the list is counted as unchanged.
- **The 2023–2024 movement test** has 18 changed games and low power.

## References

- Abadie, A., Athey, S., Imbens, G. W., and Wooldridge, J. M. (2023). When should you adjust standard errors for clustering? *The Quarterly Journal of Economics*, 138(1), 1–35. https://doi.org/10.1093/qje/qjac038
- Benjamini, Y., and Hochberg, Y. (1995). Controlling the false discovery rate: a practical and powerful approach to multiple testing. *Journal of the Royal Statistical Society, Series B*, 57(1), 289–300. https://doi.org/10.1111/j.2517-6161.1995.tb02031.x
- Berrett, T. B., Wang, Y., Barber, R. F., and Samworth, R. J. (2020). The conditional permutation test for independence while controlling for confounders. *Journal of the Royal Statistical Society, Series B*, 82(1), 175–197. https://doi.org/10.1111/rssb.12340
- Bröcker, J., and Smith, L. A. (2007). Increasing the reliability of reliability diagrams. *Weather and Forecasting*, 22(3), 651–661. https://doi.org/10.1175/WAF993.1
- Cameron, A. C., Gelbach, J. B., and Miller, D. L. (2008). Bootstrap-based improvements for inference with clustered errors. *The Review of Economics and Statistics*, 90(3), 414–427. https://doi.org/10.1162/rest.90.3.414
- Candès, E., Fan, Y., Janson, L., and Lv, J. (2018). Panning for gold: 'model-X' knockoffs for high dimensional controlled variable selection. *Journal of the Royal Statistical Society, Series B*, 80(3), 551–577. https://doi.org/10.1111/rssb.12265
- Davison, A. C., and Hinkley, D. V. (1997). *Bootstrap Methods and Their Application*. Cambridge University Press. https://doi.org/10.1017/CBO9780511802843
- Harvey, D., Leybourne, S., and Newbold, P. (1997). Testing the equality of prediction mean squared errors. *International Journal of Forecasting*, 13(2), 281–291. https://doi.org/10.1016/S0169-2070(96)00719-4
- Kline, P., and Santos, A. (2012). A score based approach to wild bootstrap inference. *Journal of Econometric Methods*, 1(1), 23–41. https://doi.org/10.1515/2156-6674.1006
- MacKinnon, J. G., Nielsen, M. Ø., and Webb, M. D. (2023). Cluster-robust inference: a guide to empirical practice. *Journal of Econometrics*, 232(2), 272–299. https://doi.org/10.1016/j.jeconom.2022.04.001
- Pustejovsky, J. E., and Tipton, E. (2018). Small-sample methods for cluster-robust variance estimation and hypothesis testing in fixed effects models. *Journal of Business & Economic Statistics*, 36(4), 672–683. https://doi.org/10.1080/07350015.2016.1247004
- Roodman, D., MacKinnon, J. G., Nielsen, M. Ø., and Webb, M. D. (2019). Fast and wild: bootstrap inference in Stata using boottest. *The Stata Journal*, 19(1), 4–60. https://doi.org/10.1177/1536867X19830877
- NFL. Flexible scheduling procedures (the page holds the 2022 procedures; read 2026-10-28). https://www.nfl.com/news/flexible-scheduling-procedures
- NBC Sports. NFL flex schedule 2024: when can the NFL start flexing games? SNF, MNF and TNF flex rules explained. https://www.nbcsports.com/nfl/news/nfl-flex-schedule-2024-when-can-the-nfl-start-flexing-games-snf-mnf-and-tnf-flex-rules-explained
- Los Angeles Rams (2023). Thursday Night Football flex scheduling approved for 2023 season. https://www.therams.com/news/thursday-night-football-flex-scheduling-approved-for-2023-season
- Wikipedia contributors. "2018 NFL season" to "2024 NFL season", section "Scheduling changes", at the revisions in `data/wikipedia_revisions.json`. The text excerpts in `data/` are © Wikipedia contributors, licensed CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/).

## Files

**Results:**
- `s4-null-diagnostic.csv`, `s4_nulls.csv`, `s4_power.csv`: §1;
- `joint_size.csv`, `joint_size_linear.csv`: §2;
- `cluster_icc.csv`, `cluster_design_effects.csv`: §3;
- `late_tests.csv`, `late_s1_sensitivity.csv`, `late_movement.csv`: §4;
- `logs-*.txt`: the console output of the S4 and joint runs;
- `summary.txt`: the numbers.

**Data:** `data/wikipedia_revisions.json`, `data/flex-bullets.json` and `data/flex-games.csv`.

**Scripts.** All run from the root of a tree that holds the A3 files:
- `scripts/research-table.R <out.rds>` builds the close-anchored table through 2022.
- `scripts/a3-research.R <s4|joint|joint_linear|cluster|late> <table.rds> <out_dir> [extra]` runs one study. The S4 and joint sections take tens of minutes.
- `scripts/s4-null-diagnostic.R <out_csv> [B]`, `scripts/late-movement.R`, `scripts/flex-fetch.mjs`, `scripts/flex-bullets.mjs` and `scripts/flex-games.R` build the rest.
- `scripts/research-summary.R` writes `summary.txt` and needs nothing but this folder and `backtest/vvf/data/game_context.csv`.
