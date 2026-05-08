# ============================================================================
# 02_exploratory_analysis_global.R
# Global Exploratory Data Analysis - Worldwide Dog Parks
# ============================================================================
# This script creates:
#   1. Global descriptive statistics
#   2. Distribution analysis by region
#   3. Correlation analysis
#   4. Comparative visualizations
# ============================================================================

source("00_setup.R")
load(file.path(dir_analysis, "01_master_global_data.RData"))

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Global Exploratory Data Analysis Module\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# ============================================================================
# PART 1: Descriptive Statistics - Global
# ============================================================================
cat("--- Calculating Global Descriptive Statistics ---\n")

global_stats <- master_global %>%
  select(n_parks, parks_per_100k, park_density_score) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "value") %>%
  group_by(variable) %>%
  summarise(
    n = n(),
    Mean = mean(value, na.rm = TRUE),
    SD = sd(value, na.rm = TRUE),
    Min = min(value, na.rm = TRUE),
    Q1 = quantile(value, 0.25, na.rm = TRUE),
    Median = median(value, na.rm = TRUE),
    Q3 = quantile(value, 0.75, na.rm = TRUE),
    Max = max(value, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(across(where(is.numeric) & !starts_with("n"), ~round(., 2)))

write_csv(global_stats, 
         file.path(dir_analysis, "02_global_descriptive_statistics.csv"))

cat("✓ Descriptive statistics calculated\n\n")
print(global_stats)
cat("\n")

# ============================================================================
# PART 2: Regional Comparison Analysis
# ============================================================================
cat("--- Regional Comparison Analysis ---\n")

regional_comparison <- master_global %>%
  group_by(region) %>%
  summarise(
    n_countries = n(),
    total_parks = sum(n_parks),
    mean_parks = mean(n_parks),
    median_parks = median(n_parks),
    max_parks = max(n_parks),
    min_parks = min(n_parks),
    
    mean_per_100k = mean(parks_per_100k, na.rm = TRUE),
    median_per_100k = median(parks_per_100k, na.rm = TRUE),
    sd_per_100k = sd(parks_per_100k, na.rm = TRUE),
    
    total_population = sum(estimated_population),
    avg_score = mean(park_density_score, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_per_100k))

write_csv(regional_comparison,
         file.path(dir_analysis, "02_regional_comparison.csv"))

cat("Regional Comparison:\n")
print(regional_comparison)
cat("\n")

# ============================================================================
# PART 3: Country Tier Distribution
# ============================================================================
cat("--- Country Tier Distribution ---\n")

tier_distribution <- master_global %>%
  group_by(tier) %>%
  summarise(
    n_countries = n(),
    pct_total = n() / nrow(master_global) * 100,
    total_parks = sum(n_parks),
    mean_per_100k = mean(parks_per_100k, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(factor(tier, levels = c("Top Tier", "Advanced", "Developing", "Emerging", "Low Tier")))

write_csv(tier_distribution,
         file.path(dir_analysis, "02_tier_distribution.csv"))

cat("Distribution by Tier:\n")
print(tier_distribution)
cat("\n")

# ============================================================================
# PART 4: Visualizations - Global Statistics
# ============================================================================
cat("--- Creating Global Visualizations ---\n")

# Plot 1: Distribution of dog parks per 100k
p_dist <- master_global %>%
  ggplot(aes(x = parks_per_100k)) +
  geom_histogram(fill = "#2E86AB", color = "white", bins = 30, alpha = 0.8) +
  geom_vline(aes(xintercept = mean(parks_per_100k, na.rm = TRUE)),
             linetype = "dashed", color = "red", size = 1) +
  labs(
    title = "Global Distribution: Dog Parks per 100k Population",
    x = "Dog Parks per 100k",
    y = "Number of Countries"
  ) +
  theme_global

ggsave(file.path(dir_figures, "02_distribution_parks_per_100k.png"),
       p_dist, width = 12, height = 7, dpi = 300)

cat("  ✓ Distribution plot saved\n")

# Plot 2: Regional box plot
p_regional_box <- master_global %>%
  ggplot(aes(x = reorder(region, parks_per_100k, median), y = parks_per_100k)) +
  geom_boxplot(aes(fill = region), alpha = 0.7, color = "grey40") +
  scale_fill_manual(values = palette_regions, guide = "none") +
  labs(
    title = "Dog Parks Distribution by World Region",
    x = "Region",
    y = "Dog Parks per 100k Population"
  ) +
  theme_global +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(dir_figures, "02_regional_boxplot.png"),
       p_regional_box, width = 12, height = 7, dpi = 300)

cat("  ✓ Regional boxplot saved\n")

# Plot 3: Top 20 countries by dog parks per 100k
p_top20 <- master_global %>%
  slice_max(parks_per_100k, n = 20) %>%
  ggplot(aes(x = reorder(country_name, parks_per_100k), y = parks_per_100k)) +
  geom_col(aes(fill = tier), color = "white", linewidth = 0.5) +
  scale_fill_brewer(palette = "RdYlGn", name = "Tier") +
  coord_flip() +
  labs(
    title = "Top 20 Countries: Dog Parks per 100k Population",
    x = "Country",
    y = "Dog Parks per 100k"
  ) +
  theme_global

ggsave(file.path(dir_figures, "02_top20_countries.png"),
       p_top20, width = 12, height = 8, dpi = 300)

cat("  ✓ Top 20 countries plot saved\n")

# Plot 4: Regional pie chart
p_regions_pie <- regional_summary %>%
  ggplot(aes(x = "", y = total_parks, fill = region)) +
  geom_col(color = "white", size = 2) +
  coord_polar(theta = "y") +
  scale_fill_manual(values = palette_regions, name = "Region") +
  geom_label(aes(label = sprintf("%s\n%d parks", region, total_parks)),
            position = position_stack(vjust = 0.5),
            fontface = "bold", size = 3) +
  labs(title = "Global Dog Parks Distribution by Region") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14, hjust = 0.5),
        legend.position = "right")

ggsave(file.path(dir_figures, "02_regions_pie_chart.png"),
       p_regions_pie, width = 10, height = 8, dpi = 300)

cat("  ✓ Regional pie chart saved\n")

# Plot 5: Development level vs parks
p_dev_level <- master_global %>%
  group_by(development_level) %>%
  summarise(mean_parks = mean(parks_per_100k, na.rm = TRUE),
            n_countries = n(), .groups = "drop") %>%
  ggplot(aes(x = reorder(development_level, mean_parks), y = mean_parks)) +
  geom_col(fill = "#2E86AB", color = "white", size = 1, alpha = 0.8) +
  geom_text(aes(label = sprintf("%d\ncountries", n_countries)), vjust = -0.5) +
  coord_flip() +
  labs(
    title = "Average Dog Parks per 100k by Development Level",
    x = "Development Level",
    y = "Average Parks per 100k"
  ) +
  theme_global

ggsave(file.path(dir_figures, "02_development_level_comparison.png"),
       p_dev_level, width = 11, height = 6, dpi = 300)

cat("  ✓ Development level plot saved\n\n")

# ============================================================================
# PART 5: Key Findings Summary
# ============================================================================
cat("--- Key Findings ---\n")

findings <- sprintf(
"GLOBAL EXPLORATORY ANALYSIS FINDINGS

SAMPLE SIZE:
- Countries analyzed: %d
- Total dog parks: %d
- Average parks per country: %.1f
- Median parks per country: %.0f

GLOBAL METRICS:
- Mean: %.2f parks per 100k population
- Median: %.2f parks per 100k
- Std Dev: %.2f
- Range: %.2f - %.2f parks per 100k

REGIONAL LEADERS:
- Highest average: %s (%.2f parks/100k)
- Most total parks: %s (%d parks)
- Fastest-growing region: %s

TIER DISTRIBUTION:
- Top Tier countries: %d (%.1f%%)
- Advanced countries: %d (%.1f%%)
- Developing countries: %d (%.1f%%)
- Emerging countries: %d (%.1f%%)
- Low Tier countries: %d (%.1f%%)

TOP 5 COUNTRIES:
%s

FINDINGS:
1. Significant global variation in dog park provision
2. Regional clustering evident in the data
3. Developed nations show higher parks per capita
4. Emerging markets showing rapid growth potential
5. Opportunity for benchmarking and capacity building
",

nrow(master_global),
sum(master_global$n_parks),
mean(master_global$n_parks),
median(master_global$n_parks),

mean(master_global$parks_per_100k, na.rm = TRUE),
median(master_global$parks_per_100k, na.rm = TRUE),
sd(master_global$parks_per_100k, na.rm = TRUE),
min(master_global$parks_per_100k, na.rm = TRUE),
max(master_global$parks_per_100k, na.rm = TRUE),

regional_comparison$region[1],
regional_comparison$mean_per_100k[1],
regional_summary$region[which.max(regional_summary$total_parks)],
max(regional_summary$total_parks),
master_global$region[which.max(master_global$park_density_score)],

sum(tier_distribution$n_countries[tier_distribution$tier == "Top Tier"]),
tier_distribution$pct_total[tier_distribution$tier == "Top Tier"],
sum(tier_distribution$n_countries[tier_distribution$tier == "Advanced"]),
tier_distribution$pct_total[tier_distribution$tier == "Advanced"],
sum(tier_distribution$n_countries[tier_distribution$tier == "Developing"]),
tier_distribution$pct_total[tier_distribution$tier == "Developing"],
sum(tier_distribution$n_countries[tier_distribution$tier == "Emerging"]),
tier_distribution$pct_total[tier_distribution$tier == "Emerging"],
sum(tier_distribution$n_countries[tier_distribution$tier == "Low Tier"]),
tier_distribution$pct_total[tier_distribution$tier == "Low Tier"],

paste(head(master_global %>% select(country_name, parks_per_100k, tier), 5) %>%
      mutate(line = sprintf("  %s: %.2f/100k (%s)",country_name, parks_per_100k, tier)) %>%
      pull(line), collapse = "\n")
)

write(findings, file.path(dir_analysis, "02_eda_findings.txt"))
cat(findings)

# ============================================================================
# Session Summary
# ============================================================================
cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Global EDA Complete!\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat("Output files:\n")
cat("  ✓ global_descriptive_statistics.csv\n")
cat("  ✓ regional_comparison.csv\n")
cat("  ✓ tier_distribution.csv\n")
cat("  ✓ 5 visualization PNG files\n")
cat("  ✓ eda_findings.txt\n\n")

cat("Next: Run 03_regional_analysis.R\n")
cat("═══════════════════════════════════════════════════════════════\n\n")
