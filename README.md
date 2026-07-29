# Personality Traits and Investment Decisions

**Do the Big Five personality traits affect stock market participation, and through
which channels?** Evidence from the German Socio-Economic Panel (SOEP), 2005–2017.

Replication code for *Personality Differences and Investment Decisions: Evidence from
German Household Data*, a Master's seminar paper at the University of Münster
(Advanced Finance, Summer 2025).

---

## Research question

Standard portfolio theory predicts that households with similar wealth, income and
education should make similar investment decisions. They do not. Large shares of German
households hold no equity at all, including many with substantial financial assets.

This paper asks whether stable personality differences help explain that gap, and if so
**through which mechanism**. Personality is unlikely to affect portfolio choice directly.
The more plausible route is indirect: traits shape what people *believe* about financial
markets and how much risk they are *willing* to bear, and those in turn shape
participation.

```
Big Five traits  ──►  beliefs about markets  ──►  stock market participation
                 ──►  risk willingness      ──►
```

The design replicates and extends Jiang et al. (2024) on German data, adding formal
causal mediation analysis and a test for non-linearity.

---

## Main findings

**1. Personality predicts risk willingness strongly.** Openness (+0.424) and
Extraversion (+0.303) raise self-reported willingness to take risks; Neuroticism
(−0.285), Agreeableness (−0.265) and Conscientiousness (−0.127) lower it. All
significant at 1%. N = 38,949, R² = 0.152.

**2. Personality predicts beliefs about financial markets**, with Neuroticism the
strongest predictor of financial concern, followed by Conscientiousness. N = 21,909,
R² = 0.076.

**3. Effects on participation depend on who makes the decision.** The sample is split
into one-person households, where the personality respondent is unambiguously the
decision maker, and heads of multi-person households.

| Trait | One-person HH | Heads of multi-person HH |
|---|---|---|
| Openness | −2.129*** | −0.328 |
| Conscientiousness | −0.957* | −2.365*** |
| Extraversion | −1.153** | −0.143 |
| Agreeableness | −0.540 | −1.972*** |
| Neuroticism | −1.291*** | −0.503 |
| N | 8,663 | 15,166 |

Openness, Extraversion and Neuroticism matter for people deciding alone; Conscientiousness
and Agreeableness matter for household heads. Individual dispositions appear attenuated
when financial decisions are shared.

**4. Openness has an inverse-U relationship with participation.** The negative linear
coefficient is misleading. Adding a quadratic term gives a positive linear and negative
squared term in both subsamples (8.509 and −1.099 for one-person households; 5.873 and
−0.666 for heads, all significant at 1%). Likelihood-ratio tests confirm the quadratic
specification improves fit (p = 0.0002 and p = 0.0057). Participation rises with moderate
openness and declines at high levels.

**5. Formal mediation identifies distinct channels for two traits.** Bootstrapped causal
mediation, 1,000 replications:

| Path | ACME (indirect) | ADE (direct) | Proportion mediated |
|---|---|---|---|
| Openness → risk willingness → participation | 0.292 (p = 0.001) | 0.180 (p = 0.450) | 62% (p = 0.002) |
| Neuroticism → beliefs → participation | 0.108 (p = 0.002) | −0.443 (p = 0.280) | not identified |

Openness affects participation almost entirely through risk tolerance rather than
directly. For Neuroticism the indirect path through beliefs is significant, but the total
effect is not (p = 0.418), so the proportion mediated is not interpretable and the result
is reported as suggestive.

**6. Results survive non-linear estimation.** Logit and probit reproduce the OLS
conclusions: Conscientiousness robustly negative, Neuroticism and Extraversion weakly
negative, Openness and Agreeableness insignificant in linear form.

---

## Data

**German Socio-Economic Panel (SOEP)**, waves 2005, 2009, 2013 and 2017, the years in
which the Big Five inventory is fielded.

| Component | SOEP source | Notes |
|---|---|---|
| Big Five | `pl` | 16 items (`plh0212`–`plh0226`, `plh0255`), 4 reverse-coded, averaged, standardised |
| Stock participation | `hl` | `hlc0107_v2`, binary, rescaled to 100 |
| Beliefs | `pl` | `plh0034`, concern about financial market stability (2009, 2013) |
| Risk willingness | `pl` | `plh0204_v2` general (2009, 2013, 2017); `plh0198` financial (2009 only) |
| Demographics | `biobirth`, `pgen` | Age, sex, labour income, years of education |
| Wealth and debt | `pwealth` | Five multiply-imputed values each, averaged |
| Household role | `pbrutto` | `stell_h`, used to identify heads of household |

SOEP is not redistributable. Access is free for research use via
[diw.de/soep](https://www.diw.de/soep). See `data/README.md` for the required files.

---

## Method

**Estimation.** OLS with HC1 heteroskedasticity-robust standard errors. Participation is
scaled to percentage points so coefficients read as percentage-point effects. Because a
linear probability model on a binary outcome can generate fitted values outside the unit
interval, logit and probit are estimated as robustness checks.

**Identifying the decision maker.** Personality is measured for individuals but stock
ownership is recorded at household level. In multi-person households the personality
respondent is not necessarily the investor, so the sample is split and results are
reported separately.

**Mediation.** Three steps: the effect of each trait on each mediator; a baseline
participation model compared with one adding the mediators, so that coefficient shrinkage
is visible; and formal causal mediation with bootstrapped confidence intervals following
Imai, Keele and Tingley (2010).

**Non-linearity.** The quadratic specification for Openness is tested rather than
imposed, via likelihood-ratio tests against the linear model, with the predicted
participation profile plotted across the observed range.

**Measurement diagnostics.** Principal component analysis on the personality items checks
construct validity. Most load cleanly, but the aesthetic-appreciation and
abstract-thinking items (`plh0225`, `plh0255`) load diffusely, which motivates cautious
interpretation of the Openness results and is consistent with the non-linearity found.

---

## Repository contents

```
├── Seminar_Advanced_Finance.R    Full pipeline: cleaning, construction, estimation, figures
├── data/README.md                SOEP access instructions and required files
└── results/                      Regression tables and figures
```

The script runs top to bottom and produces the regression tables (LaTeX via `stargazer`)
and the figures used in the paper.

## Requirements

R ≥ 4.0.0:

```r
install.packages(c("dplyr", "tidyr", "ggplot2", "lmtest", "sandwich",
                   "broom", "stargazer", "e1071", "mediation",
                   "knitr", "gridExtra"))
```

---

## Limitations

**Wealth imputation.** The SOEP wealth module is not fielded in every wave, so wealth and
debt are carried across waves. This assumes sufficient persistence over multi-year
horizons and is flagged in the figures.

**Cross-sectional identification.** The Big Five are stable by construction, so
within-person variation is limited and panel fixed effects are uninformative here.
Estimates are conditional associations rather than causal effects. The mediation analysis
identifies indirect paths under sequential-ignorability assumptions that cannot be
verified with these data.

**Mediation without a total effect.** For Neuroticism the total effect on participation
is statistically insignificant, so the significant indirect path is treated as suggestive
rather than as established mediation.

**Openness measurement.** The PCA diagnostics indicate the Openness items are less
unidimensional than the other traits, which may contribute to the non-linear pattern.

**The belief channel may run backwards.** The SOEP concern item `plh0034` is coded
1 = very concerned, 2 = somewhat concerned, 3 = not concerned at all, so lower values
mean more worry. The code reverses it (`worry_index = 4 - plh0034`) so that higher values
mean more concern and coefficients read directly. On that coding, greater concern about
market stability is associated with *higher* participation, which is hard to reconcile
with a belief channel operating as theorised but is what reverse causality would produce:
households holding equity monitor markets and therefore report more concern. The
Neuroticism mediation result should be read as an association rather than as evidence
that pessimism causes non-participation. Signs in the code are the mirror image of those
in the original paper, which used the raw scale.

---

## References

Jiang, Z., Peng, C. and Yan, H. (2024). Personality differences and investment
decision-making.

Imai, K., Keele, L. and Tingley, D. (2010). A general approach to causal mediation
analysis. *Psychological Methods* 15(4), 309–334.

Personality items follow the SOEP short version of the Big Five Inventory (BFI-S).
