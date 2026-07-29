# =============================================================================
# Personality Traits and Investment Decisions
# Evidence from the German Socio-Economic Panel (SOEP), 2005-2017
#
# Pipeline: cleaning -> Big Five construction -> belief and risk regressions
#           -> participation regressions -> mediation -> robustness -> figures
#
# Requires the SOEP files listed in data/README.md to be present in the working
# directory. SOEP is not redistributable; access is free for research use via
# https://www.diw.de/soep
# =============================================================================

# Set the working directory to the folder containing the SOEP extracts before
# running, e.g. via the RStudio project or setwd("path/to/data").

library(dplyr)
library(tidyr)
library(ggplot2)
library(lmtest)
library(sandwich)
library(broom)
library(stargazer)
library(e1071)
library(mediation)


# =============================================================================
# 1. LOAD AND CLEAN
# =============================================================================

load("pl.RData")

pl <- pl %>%
  select(pid, hid, syear, plh0212:plh0226, plh0255,
         pla0009_h, plh0034, plh0198, plh0204_v2)

# SOEP codes all missingness as negative values (-1 no answer, -2 does not
# apply, -8 question not asked this year, etc). These must become NA before any
# averaging, or they would be treated as valid low scores.
pl[sapply(pl, is.numeric)] <- lapply(pl[sapply(pl, is.numeric)],
                                     function(x) ifelse(x < 0, NA, x))
pl <- pl[!apply(is.na(pl), 1, all), ]

# Household size, used later to separate one-person households from the rest
hh_sizes <- pl %>%
  group_by(hid, syear) %>%
  summarise(hh_size = n_distinct(pid), .groups = "drop")
pl <- merge(pl, hh_sizes, by = c("hid", "syear"))


# =============================================================================
# 2. BIG FIVE CONSTRUCTION
# =============================================================================
# 16 items on a 7-point scale. Four are worded in the opposite direction to the
# trait they measure and are reversed so that a higher score always means more
# of the trait.

reverse_7pt <- function(x) ifelse(is.na(x), NA, 8 - x)

pl <- pl %>%
  mutate(
    plh0214_r = reverse_7pt(plh0214),   # "finds fault with others"  -> Agreeableness
    plh0218_r = reverse_7pt(plh0218),   # "tends to be lazy"         -> Conscientiousness
    plh0223_r = reverse_7pt(plh0223),   # "is reserved"              -> Extraversion
    plh0226_r = reverse_7pt(plh0226)    # "is relaxed, handles stress" -> Neuroticism
  )

pl <- pl %>%
  mutate(
    openness_raw          = rowMeans(select(., plh0215, plh0220, plh0225, plh0255), na.rm = TRUE),
    conscientiousness_raw = rowMeans(select(., plh0212, plh0218_r, plh0222),        na.rm = TRUE),
    extraversion_raw      = rowMeans(select(., plh0213, plh0219, plh0223_r),        na.rm = TRUE),
    agreeableness_raw     = rowMeans(select(., plh0214_r, plh0217, plh0224),        na.rm = TRUE),
    neuroticism_raw       = rowMeans(select(., plh0216, plh0221, plh0226_r),        na.rm = TRUE)
  ) %>%
  mutate(across(ends_with("_raw"),
                ~ as.numeric(scale(.)),
                .names = "{sub('_raw', '_standardized', .col)}"))


# =============================================================================
# 3. BELIEF AND RISK MEASURES
# =============================================================================
#
# IMPORTANT - CODING OF THE BELIEF ITEM
#
# plh0034 "worried about stability of financial markets" is coded
#     1 = Very concerned
#     2 = Somewhat concerned
#     3 = Not concerned at all
# so LOWER values mean MORE worry. Leaving it on the raw scale makes every
# downstream coefficient read backwards, so it is reversed here:
#
#     worry_index = 4 - plh0034   ->   1 = not concerned ... 3 = very concerned
#
# Higher worry_index now means more concern, and coefficients can be read
# directly. Note that signs are therefore the mirror image of those in the
# original paper, which reported the raw scale.

pl <- pl %>%
  mutate(
    worry_index    = 4 - plh0034,                 # higher = more worried
    risk_general   = plh0204_v2,                  # 0-10, higher = more risk tolerant
    risk_financial = plh0198                      # 0-10, 2009 only
  )


# =============================================================================
# 4. OUTCOME, CONTROLS AND SAMPLE
# =============================================================================

hl <- read.csv("hl.csv") %>% select(hid, syear, hlc0107_v2)
pl <- merge(pl, hl, by = c("hid", "syear"), all.x = TRUE)

pl <- pl %>%
  mutate(stock_participation = ifelse(hlc0107_v2 == 1, 1,
                                      ifelse(!is.na(hlc0107_v2), 0, NA)))

# Waves in which the Big Five inventory is fielded
pl <- pl %>%
  filter(syear %in% c(2005, 2009, 2013, 2017), !is.na(stock_participation)) %>%
  mutate(stock_participation = stock_participation * 100)   # percentage points

# Demographics
biobirth <- read.csv("biobirth.csv") %>% select(pid, gebjahr, sex)
biobirth$sex[!biobirth$sex %in% c(1, 2)] <- NA
biobirth <- biobirth %>% mutate(sex_female = ifelse(sex == 2, 1, ifelse(sex == 1, 0, NA)))
pl <- merge(pl, biobirth, by = "pid", all.x = TRUE)
pl$age <- pl$syear - pl$gebjahr

# Income and education
pgen <- read.csv("pgen.csv") %>%
  select(pid, syear, pglabnet, pgbilzeit) %>%
  mutate(across(where(is.numeric), ~ ifelse(. < 0, NA, .)))
pl <- merge(pl, pgen, by = c("pid", "syear"), all.x = TRUE)

# Wealth and debt. SOEP supplies five multiple imputations of each; these are
# averaged. The module is not fielded every wave, so values are carried forward
# from the nearest preceding module (2002 -> 2005, 2009; 2007 -> 2013). This
# assumes wealth is persistent over three to six years, which is a strong
# assumption and is flagged in the paper and in Figure 1.
pwealth <- read.csv("pwealth.csv") %>% select(pid, syear, w0111a:w0111e, w0011a:w0011e)
pwealth[pwealth < 0] <- NA
pwealth <- pwealth %>%
  rowwise() %>%
  mutate(
    net_wealth = mean(c_across(c(w0111a, w0111b, w0111c, w0111d, w0111e)), na.rm = TRUE),
    net_debt   = mean(c_across(c(w0011a, w0011b, w0011c, w0011d, w0011e)), na.rm = TRUE)
  ) %>%
  ungroup() %>%
  select(pid, syear, net_wealth, net_debt)

pl$syear      <- as.integer(as.character(pl$syear))
pwealth$syear <- as.integer(as.character(pwealth$syear))

for (target_year in c(2005, 2009, 2013)) {
  donor_year <- if (target_year %in% c(2005, 2009)) 2002 else 2007
  donor <- pwealth %>%
    filter(syear == donor_year) %>%
    select(pid, net_wealth, net_debt) %>%
    mutate(syear = target_year)
  pwealth <- bind_rows(pwealth, donor)
}
pl <- merge(pl, pwealth, by = c("pid", "syear"), all.x = TRUE)

# Rescale monetary variables to thousands of euros
pl <- pl %>%
  mutate(pglabnet_k   = pglabnet   / 1000,
         net_wealth_k = net_wealth / 1000,
         net_debt_k   = net_debt   / 1000,
         year_2005 = as.integer(syear == 2005),
         year_2009 = as.integer(syear == 2009),
         year_2013 = as.integer(syear == 2013))

# Separating the decision maker. Personality is measured per individual but
# stock ownership is recorded per household, so in multi-person households the
# personality respondent need not be the investor. One-person households are
# unambiguous; for the rest we keep only the household head.
pbrutto <- read.csv("pbrutto.csv") %>%
  select(pid, syear, stell_h) %>%
  mutate(stell_h = ifelse(stell_h < 0, NA, stell_h),
         head_of_household = ifelse(stell_h == 0, 1, 0))

pl_oneperson   <- pl %>% filter(hh_size == 1)
pl_multiperson <- pl %>% filter(hh_size > 1) %>%
  merge(pbrutto, by = c("pid", "syear"), all.x = TRUE)
pl_heads <- pl_multiperson %>% filter(head_of_household == 1)


# =============================================================================
# 5. HELPERS
# =============================================================================

TRAITS <- c("openness_standardized", "conscientiousness_standardized",
            "extraversion_standardized", "agreeableness_standardized",
            "neuroticism_standardized")

fit_robust <- function(formula, data) {
  m <- lm(formula, data = data)
  list(model = m,
       se    = sqrt(diag(vcovHC(m, type = "HC1"))),
       test  = coeftest(m, vcov. = vcovHC(m, type = "HC1")))
}


# =============================================================================
# 6. BELIEF CHANNEL
# =============================================================================
# Available in 2009 and 2013 only.

pl_beliefs <- pl %>%
  filter(syear %in% c(2009, 2013), !is.na(worry_index))

f_beliefs <- as.formula(paste("worry_index ~", paste(TRAITS, collapse = " + "),
                              "+ age + sex_female + pglabnet_k + pgbilzeit + year_2009"))
res_beliefs <- fit_robust(f_beliefs, pl_beliefs)
print(res_beliefs$test)

# With worry_index reversed, a POSITIVE coefficient means the trait is
# associated with greater concern about financial markets.


# =============================================================================
# 7. PREFERENCE CHANNEL
# =============================================================================

# General risk willingness, 2009 / 2013 / 2017
pl_genrisk <- pl %>% filter(syear %in% c(2009, 2013, 2017), !is.na(risk_general))
f_risk <- as.formula(paste("risk_general ~", paste(TRAITS, collapse = " + "),
                           "+ age + sex_female + pglabnet_k + pgbilzeit + year_2009 + year_2013"))
res_risk <- fit_robust(f_risk, pl_genrisk)
print(res_risk$test)

# Financial vs general risk, 2009 only, as a robustness comparison
pl_risk_2009 <- pl %>% filter(syear == 2009)
f_fin <- as.formula(paste("risk_financial ~", paste(TRAITS, collapse = " + "),
                          "+ age + sex_female + pglabnet_k + pgbilzeit + net_wealth_k + net_debt_k"))
f_gen <- update(f_fin, risk_general ~ .)
res_fin <- fit_robust(f_fin, pl_risk_2009)
res_gen <- fit_robust(f_gen, pl_risk_2009)


# =============================================================================
# 8. PARTICIPATION, BY DECISION-MAKER TYPE
# =============================================================================

f_part <- as.formula(paste(
  "stock_participation ~", paste(TRAITS, collapse = " + "),
  "+ age + pglabnet_k + net_wealth_k + net_debt_k + sex_female + pgbilzeit",
  "+ year_2005 + year_2009 + year_2013"))

res_oneperson <- fit_robust(f_part, pl_oneperson)
res_heads     <- fit_robust(f_part, pl_heads)
print(res_oneperson$test)
print(res_heads$test)


# =============================================================================
# 9. NON-LINEARITY IN OPENNESS
# =============================================================================
# The negative linear coefficient on Openness is inconsistent with theory. The
# quadratic specification is tested rather than assumed, via a likelihood-ratio
# test against the linear model.

pl_oneperson <- pl_oneperson %>% mutate(openness_sq = openness_raw^2)
pl_heads     <- pl_heads     %>% mutate(openness_sq = openness_raw^2)

f_quad <- stock_participation ~ openness_raw + openness_sq +
  conscientiousness_raw + extraversion_raw + agreeableness_raw + neuroticism_raw +
  age + pglabnet_k + net_wealth_k + net_debt_k + sex_female + pgbilzeit +
  year_2005 + year_2009 + year_2013

f_lin <- update(f_quad, . ~ . - openness_sq)

res_quad_one   <- fit_robust(f_quad, pl_oneperson)
res_quad_heads <- fit_robust(f_quad, pl_heads)

print(lrtest(lm(f_lin, data = pl_oneperson), lm(f_quad, data = pl_oneperson)))
print(lrtest(lm(f_lin, data = pl_heads),     lm(f_quad, data = pl_heads)))

# Predicted participation across the observed range of Openness
plot_data <- data.frame(openness_raw = seq(min(pl_oneperson$openness_raw, na.rm = TRUE),
                                           max(pl_oneperson$openness_raw, na.rm = TRUE),
                                           length.out = 100)) %>%
  mutate(openness_sq = openness_raw^2)
means <- pl_oneperson %>%
  summarise(across(c(conscientiousness_raw, extraversion_raw, agreeableness_raw,
                     neuroticism_raw, age, pglabnet_k, net_wealth_k, net_debt_k,
                     sex_female, pgbilzeit, year_2005, year_2009, year_2013),
                   ~ mean(., na.rm = TRUE)))
plot_data <- cbind(plot_data, means[rep(1, 100), ])
plot_data$predicted <- predict(res_quad_one$model, newdata = plot_data)

ggplot(plot_data, aes(x = openness_raw, y = predicted)) +
  geom_line(colour = "steelblue", linewidth = 1) +
  labs(title = "Predicted Stock Market Participation by Openness",
       x = "Openness (raw score)", y = "Predicted participation (%)") +
  theme_minimal(base_size = 14)


# =============================================================================
# 10. MEDIATION
# =============================================================================
# Does personality reach participation through beliefs and risk attitudes?
# Step one compares a baseline model with one containing the mediators, so that
# coefficient shrinkage is visible. Step two runs formal causal mediation.

pl_med <- pl %>%
  filter(syear %in% c(2009, 2013), !is.na(stock_participation)) %>%
  filter(complete.cases(across(all_of(c("stock_participation", TRAITS,
                                        "risk_general", "worry_index", "age",
                                        "sex_female", "pglabnet_k", "pgbilzeit",
                                        "net_wealth_k", "net_debt_k", "year_2009")))))

f_base <- as.formula(paste(
  "stock_participation ~", paste(TRAITS, collapse = " + "),
  "+ age + sex_female + pglabnet_k + pgbilzeit + net_wealth_k + net_debt_k + year_2009"))
f_mech <- update(f_base, . ~ . + worry_index + risk_general)

res_base <- fit_robust(f_base, pl_med)
res_mech <- fit_robust(f_mech, pl_med)
print(res_base$test)
print(res_mech$test)

# ---- Openness through risk willingness ----
med_open <- mediate(
  model.m = lm(risk_general ~ openness_standardized + age + sex_female +
                 pglabnet_k + pgbilzeit + year_2009, data = pl_med),
  model.y = lm(stock_participation ~ openness_standardized + risk_general + age +
                 sex_female + pglabnet_k + pgbilzeit + net_wealth_k + net_debt_k +
                 year_2009, data = pl_med),
  treat = "openness_standardized", mediator = "risk_general",
  boot = TRUE, sims = 1000)
summary(med_open)

# ---- Neuroticism through beliefs ----
#
# CAUTION ON INTERPRETATION
# The mediation framework assumes beliefs cause participation. The data are
# consistent with the reverse: households that own equity monitor markets and
# therefore report greater concern about market stability. With worry_index
# coded so that higher means more worried, the estimated association between
# worry and participation is POSITIVE, which is difficult to reconcile with a
# belief channel operating as theorised but is exactly what reverse causality
# would produce. The indirect effect below should be read as an association,
# not as evidence that pessimism causes non-participation. Note also that the
# total effect of Neuroticism on participation is statistically insignificant
# in this sample, so the proportion mediated is not interpretable.
med_neuro <- mediate(
  model.m = lm(worry_index ~ neuroticism_standardized + age + sex_female +
                 pglabnet_k + pgbilzeit + year_2009, data = pl_med),
  model.y = lm(stock_participation ~ neuroticism_standardized + worry_index +
                 age + sex_female + pglabnet_k + pgbilzeit + net_wealth_k +
                 net_debt_k + year_2009, data = pl_med),
  treat = "neuroticism_standardized", mediator = "worry_index",
  boot = TRUE, sims = 1000)
summary(med_neuro)


# =============================================================================
# 11. ROBUSTNESS: LOGIT AND PROBIT
# =============================================================================
# The main specification is a linear probability model, chosen so that
# coefficients read as percentage-point effects. Because an LPM can produce
# fitted values outside the unit interval, the same specification is estimated
# with logit and probit links.

f_glm <- as.formula(paste(
  "I(stock_participation / 100) ~", paste(TRAITS, collapse = " + "),
  "+ age + sex_female + pglabnet_k + pgbilzeit + net_wealth_k + net_debt_k",
  "+ year_2009 + year_2013"))

summary(glm(f_glm, data = pl_med, family = binomial(link = "logit")))
summary(glm(f_glm, data = pl_med, family = binomial(link = "probit")))


# =============================================================================
# 12. CONSTRUCT VALIDITY: PCA ON THE PERSONALITY ITEMS
# =============================================================================
# Checks whether the 16 items group as the five-factor model predicts. Most load
# cleanly; the aesthetic-appreciation (plh0225) and abstract-thinking (plh0255)
# items load diffusely, which motivates cautious interpretation of Openness and
# is consistent with the non-linearity found in Section 9.

pca_items <- pl %>%
  select(plh0212, plh0213, plh0214_r, plh0215, plh0216, plh0217, plh0218_r,
         plh0219, plh0220, plh0221, plh0222, plh0223_r, plh0224, plh0225,
         plh0226_r, plh0255) %>%
  filter(complete.cases(.))

pca_fit <- prcomp(pca_items, scale. = TRUE)
print(round(pca_fit$rotation[, 1:3], 2))
print(round(summary(pca_fit)$importance[, 1:3], 3))


# =============================================================================
# 13. DESCRIPTIVES AND FIGURES
# =============================================================================

summary_stats <- pl %>%
  transmute(Female = sex_female, Age = age,
            `Net labour income (k EUR)` = pglabnet_k,
            `Net wealth (k EUR)` = net_wealth_k,
            `Net debt (k EUR)` = net_debt_k,
            `Years of education` = pgbilzeit,
            Agreeableness = agreeableness_raw, Conscientiousness = conscientiousness_raw,
            Neuroticism = neuroticism_raw, Extraversion = extraversion_raw,
            Openness = openness_raw) %>%
  summarise(across(everything(),
                   list(Mean = ~mean(., na.rm = TRUE), SD = ~sd(., na.rm = TRUE),
                        P10 = ~quantile(., .10, na.rm = TRUE),
                        P50 = ~quantile(., .50, na.rm = TRUE),
                        P90 = ~quantile(., .90, na.rm = TRUE),
                        Skew = ~skewness(., na.rm = TRUE)),
                   .names = "{.col}__{.fn}")) %>%
  pivot_longer(everything(), names_to = c("Variable", "Statistic"), names_sep = "__") %>%
  pivot_wider(names_from = Statistic, values_from = value)
print(as.data.frame(summary_stats))

# Correlation matrix of the Big Five
print(round(cor(pl %>% select(ends_with("_raw")), use = "pairwise.complete.obs"), 2))

# Distribution of the traits
pl %>%
  select(ends_with("_raw")) %>%
  pivot_longer(everything(), names_to = "trait", values_to = "score") %>%
  mutate(trait = tools::toTitleCase(sub("_raw", "", trait))) %>%
  ggplot(aes(x = score)) +
  geom_histogram(bins = 20, fill = "gray90", colour = "black") +
  facet_wrap(~ trait, scales = "free", nrow = 1) +
  labs(x = "Trait score", y = "Count", title = "Distribution of Big Five Personality Traits") +
  theme_minimal(base_size = 14)
