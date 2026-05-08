# ============================================================================
# 04_global_ranking.R
# Global Ranking & Scoring Analysis
# ============================================================================
# This script creates:
#   1. Comprehensive global country rankings
#   2. Scoring methodology and visualization
#   3. Tier classification
#   4. Improvement potential analysis
# ============================================================================

source("00_setup.R")
load(file.path(dir_analysis, "01_master_global_data.RData"))

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Global Ranking & Scoring Module\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# ============================================================================
# PART 1: Comprehensive Scoring System
# ============================================================================
cat("--- Building Comprehensive Scoring System ---\n")

scoring_system <- master_global %>%
  mutate(
    # Primary metric: Parks per 100k (0-100 scale)
    score_parks = standardize_to_100(parks_per_100k),
    
    # Secondary metrics (placeholder for World Bank data integration)
    # These would come from subsequent data integration
    score_urbanization = 50,  # Placeholder
    score_wealth = 50,        # Placeholder
    score_health = 50,        # Placeholder
    
    # Composite Score (weighted average)
    weight_parks = 0.50,
    weight_urbanization = 0.20,
    weight_wealth = 0.15,
    weight_health = 0.15,
    
    composite_score = (score_parks * weight_parks +
                      score_urbanization * weight_urbanization +
                      score_wealth * weight_wealth +
                      score_health * weight_health),
    
    # Global ranking
    global_rank = rank(-composite_score, ties.method = "min"),
    global_percentile = (n() - global_rank + 1) / n() * 100,
    
    # Tier classification
    tier_numeric = case_when(
      composite_score >= 75 ~ "Top Tier",
      composite_score >= 60 ~ "Advanced",
      composite_score >= 45 ~ "Developing",
      composite_score >= 30 ~ "Emerging",
      TRUE ~ "Low Tier"
    ),
    
    # Performance indicators
    performance_status = case_when(
      global_percentile >= 75 ~ "Global Leader",
      global_percentile >= 50 ~ "Above Global Average",
      global_percentile >= 25 ~ "Below Global Average",
      TRUE ~ "Needs Urgent Improvement"
    )
  ) %>%
  select(country_code, country_name, region, continent,
         n_parks, parks_per_100k, score_parks,
         composite_score, global_rank, global_percentile, 
         tier_numeric, performance_status, estimated_population,
         everything())

write_csv(scoring_system %>%
         select(country_name, region, parks_per_100k, global_rank, 
                global_percentile, tier_numeric, performance_status),
         file.path(dir_analysis, "04_global_ranking_full.csv"))

cat("✓ Scoring system created\n\n")

# ============================================================================
# PART 2: Top 50 & Bottom 50 Rankings
# ============================================================================
cat("--- Top and Bottom Performers ---\n")

top_50 <- scoring_system %>%
  slice_head(n = 50) %>%
  select(global_rank, country_name, region, parks_per_100k, 
         global_percentile, tier_numeric, performance_status)

bottom_50 <- scoring_system %>%
  slice_tail(n = 50) %>%
  select(global_rank, country_name, region, parks_per_100k,
         global_percentile, tier_numeric, performance_status)

write_csv(top_50, file.path(dir_analysis, "04_top_50_countries.csv"))
write_csv(bottom_50, file.path(dir_analysis, "04_bottom_50_countries.csv"))

cat("Top 20 Countries:\n")
print(head(top_50, 20))

cat("\n\nBottom 20 Countries:\n")
print(tail(bottom_50, 20))
cat("\n")

# ============================================================================
# PART 3: Tier Distribution & Analysis
# ============================================================================
cat("--- Tier Classification Analysis ---\n")

tier_analysis <- scoring_system %>%
  group_by(tier_numeric) %>%
  summarise(
    n_countries = n(),
    pct_global = n() / nrow(.) * 100,
    total_parks = sum(n_parks),
    mean_parks_per_100k = mean(parks_per_100k, na.rm = TRUE),
    mean_composite_score = mean(composite_score, na.rm = TRUE),
    total_population = sum(estimated_population),
    avg_population = mean(estimated_population),
    .groups = "drop"
  ) %>%
  arrange(factor(tier_numeric, 
         levels = c("Top Tier", "Advanced", "Developing", "Emerging", "Low Tier")))

write_csv(tier_analysis, 
         file.path(dir_analysis, "04_tier_analysis.csv"))

cat("Tier Distribution:\n")
print(tier_analysis)
cat("\n")

# ============================================================================
# PART 4: Regional Leaders by Tier
# ============================================================================
cat("--- Regional Leaders by Tier ---\n")

regional_tier_leaders <- scoring_system %>%
  group_by(region, tier_numeric) %>%
  slice_head(n = 1) %>%
  select(country_name, region, tier_numeric, parks_per_100k, 
         global_rank, global_percentile) %>%
  arrange(region, factor(tier_numeric, 
         levels = c("Top Tier", "Advanced", "Developing", "Emerging", "Low Tier")))

cat("Sample of tier leaders by region:\n")
print(head(regional_tier_leaders, 15))
cat("\n")

# ============================================================================
# PART 5: Improvement Potential Analysis
# ============================================================================
cat("--- Improvement Potential Analysis ---\n")

improvement_potential <- scoring_system %>%
  group_by(tier_numeric) %>%
  mutate(
    tier_avg_score = mean(composite_score),
    tier_leader_score = max(composite_score),
    .groups = "drop"
  ) %>%
  mutate(
    gap_to_next_tier = case_when(
      tier_numeric == "Top Tier" ~ tier_avg_score - composite_score,
      tier_numeric == "Advanced" ~ 75 - composite_score,
      tier_numeric == "Developing" ~ 60 - composite_score,
      tier_numeric == "Emerging" ~ 45 - composite_score,
      TRUE ~ 30 - composite_score
    ),
    
    gap_to_tier_leader = tier_leader_score - composite_score,
    
    potential_percentile = composite_score / max(scoring_system$composite_score) * 100,
    
    # Improvement opportunity score
    improvement_opportunity = case_when(
      gap_to_next_tier > 10 ~ "High",
      gap_to_next_tier > 5 ~ "Medium",
      TRUE ~ "Low"
    )
  ) %>%
  arrange(desc(gap_to_next_tier)) %>%
  select(country_name, region, tier_numeric, composite_score, global_rank,
         gap_to_next_tier, improvement_opportunity)

cat("Highest improvement potential (countries closest to next tier):\n")
print(head(improvement_potential %>% filter(improvement_opportunity == "High"), 15))
cat("\n")

write_csv(improvement_potential,
         file.path(dir_analysis, "04_improvement_potential.csv"))

# ============================================================================
# PART 6: Visualizations
# ============================================================================
cat("--- Creating Ranking Visualizations ---\n")

# Plot 1: Top 30 countries
p_top30 <- scoring_system %>%
  slice_head(n = 30) %>%
  ggplot(aes(x = reorder(country_name, composite_score), y = composite_score)) +
  geom_col(aes(fill = tier_numeric), color = "white", linewidth = 0.5) +
  scale_fill_brewer(palette = "RdYlGn", name = "Tier") +
  coord_flip() +
  labs(
    title = "Top 30 Countries: Global Composite Score",
    subtitle = "Based on dog parks per 100k population",
    x = "Country",
    y = "Composite Score (0-100)"
  ) +
  theme_global

ggsave(file.path(dir_figures, "04_top_30_countries.png"),
       p_top30, width = 12, height = 10, dpi = 300)

cat("  ✓ Top 30 countries plot saved\n")

# Plot 2: Tier distribution pie chart
p_tier_pie <- tier_analysis %>%
  ggplot(aes(x = "", y = n_countries, fill = tier_numeric)) +
  geom_col(color = "white", linewidth = 1) +
  coord_polar(theta = "y") +
  scale_fill_brewer(palette = "RdYlGn", name = "Tier") +
  geom_label(aes(label = sprintf("%s\n%d\n(%.1f%%)", tier_numeric, n_countries, pct_global)),
            position = position_stack(vjust = 0.5),
            fontface = "bold", size = 3.5) +
  labs(title = "Global Tier Distribution") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14, hjust = 0.5))

ggsave(file.path(dir_figures, "04_tier_distribution_pie.png"),
       p_tier_pie, width = 10, height = 8, dpi = 300)

cat("  ✓ Tier distribution pie chart saved\n")

# Plot 3: Score distribution histogram
p_score_dist <- scoring_system %>%
  ggplot(aes(x = composite_score)) +
  geom_histogram(fill = "#2E86AB", color = "white", bins = 25, alpha = 0.8) +
  geom_vline(aes(xintercept = mean(composite_score)), linetype = "dashed", 
            color = "red", linewidth = 1) +
  facet_wrap(~ tier_numeric, scales = "free_y") +
  labs(
    title = "Score Distribution Across Tiers",
    x = "Composite Score",
    y = "Number of Countries"
  ) +
  theme_global

ggsave(file.path(dir_figures, "04_score_distribution_by_tier.png"),
       p_score_dist, width = 14, height = 8, dpi = 300)

cat("  ✓ Score distribution saved\n")

# Plot 4: Global percentile scatter
p_scatter <- scoring_system %>%
  ggplot(aes(x = parks_per_100k, y = composite_score)) +
  geom_point(aes(color = tier_numeric, size = estimated_population), alpha = 0.6) +
  scale_color_brewer(palette = "RdYlGn", name = "Tier") +
  scale_size_continuous(name = "Population", trans = "log10") +
  geom_smooth(method = "lm", color = "grey40", alpha = 0.2, se = TRUE) +
  labs(
    title = "Dog Parks per 100k vs. Composite Score",
    subtitle = "Size represents population",
    x = "Dog Parks per 100k",
    y = "Composite Score"
  ) +
  theme_global

ggsave(file.path(dir_figures, "04_scatter_score_analysis.png"),
       p_scatter, width = 12, height = 8, dpi = 300)

cat("  ✓ Scatter plot saved\n\n")

# ============================================================================
# PART 7: Summary Report
# ============================================================================
cat("--- Ranking Summary Report ---\n")

summary_text <- sprintf(
"GLOBAL RANKING & SCORING ANALYSIS

METHODOLOGY:
- Primary Metric: Dog Parks per 100k Population (50%%)
- Secondary Placeholders: Urbanization (20%%), Wealth (15%%), Health (15%%)
- Scoring Range: 0-100 (higher = better)
- Tiers: Top Tier (≥75), Advanced (60-74), Developing (45-59), Emerging (30-44), Low Tier (<30)

GLOBAL DISTRIBUTION:
- Total countries ranked: %d
- Average composite score: %.1f
- Median composite score: %.1f
- Score range: %.1f - %.1f

TIER BREAKDOWN:
%s

TOP 5 COUNTRIES:
%s

BOTTOM 5 COUNTRIES:
%s

IMPROVEMENT OPPORTUNITIES:
- High potential (gap > 10 pts to next tier): %d countries
- Medium potential (gap 5-10 pts): %d countries
- Low potential (gap < 5 pts): %d countries

KEY INSIGHTS:
1. Significant global variation exists in dog park provision
2. Only %d countries in Top Tier - indicates growth opportunity
3. %d countries in Low Tier - urgent improvement needed
4. Regional leaders can serve as mentors for laggards
5. Peer learning within regions more effective than global comparison

NEXT STEPS:
- Integrate World Bank data for urbanization/wealth/health metrics
- Refine scoring methodology with actual development indicators
- Identify quick wins for improvement in Low Tier countries
- Create peer learning groups within regions
",

nrow(scoring_system),
mean(scoring_system$composite_score),
median(scoring_system$composite_score),
min(scoring_system$composite_score),
max(scoring_system$composite_score),

tier_analysis %>%
  rowwise() %>%
  mutate(line = sprintf("  %s: %d countries (%.1f%%) - avg score: %.1f",
         tier_numeric, n_countries, pct_global, mean_composite_score)) %>%
  pull(line) %>% paste(collapse = "\n"),

head(scoring_system, 5) %>%
  rowwise() %>%
  mutate(line = sprintf("  #%d - %s: %.2f parks/100k (%s)",
          global_rank, country_name, parks_per_100k, tier_numeric)) %>%
  pull(line) %>% paste(collapse = "\n"),

tail(scoring_system, 5) %>%
  rowwise() %>%
  mutate(line = sprintf("  #%d - %s: %.2f parks/100k (%s)",
          global_rank, country_name, parks_per_100k, tier_numeric)) %>%
  pull(line) %>% paste(collapse = "\n"),

sum(improvement_potential$improvement_opportunity == "High"),
sum(improvement_potential$improvement_opportunity == "Medium"),
sum(improvement_potential$improvement_opportunity == "Low"),

sum(tier_analysis$tier_numeric == "Top Tier"),
sum(tier_analysis$tier_numeric == "Low Tier")
)

write(summary_text, file.path(dir_analysis, "04_ranking_summary.txt"))
cat(summary_text)

# ============================================================================
# Session Summary
# ============================================================================
cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Global Ranking Analysis Complete!\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat("Output files:\n")
cat("  ✓ global_ranking_full.csv\n")
cat("  ✓ top_50_countries.csv\n")
cat("  ✓ bottom_50_countries.csv\n")
cat("  ✓ tier_analysis.csv\n")
cat("  ✓ improvement_potential.csv\n")
cat("  ✓ 4 visualization PNG files\n")
cat("  ✓ ranking_summary.txt\n\n")

cat("Next: Run 05_country_clustering.R\n")
cat("═══════════════════════════════════════════════════════════════\n\n")
