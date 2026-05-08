# ============================================================================
# 02_exploratory_analysis.R
# Exploratory Data Analysis & Descriptive Statistics
# ============================================================================
# This script creates:
#   1. Descriptive statistics tables
#   2. Distribution analysis
#   3. Correlation analysis
#   4. Initial exploratory visualizations
# ============================================================================

source("00_setup.R")
load(file.path(dir_analysis, "01_integrated_data.RData"))

cat("\n===============================================\n")
cat("Exploratory Data Analysis Module\n")
cat("===============================================\n\n")

# ============================================================================
# PART 1: Descriptive Statistics - Hong Kong Districts
# ============================================================================
cat("--- Generating Descriptive Statistics ---\n")

hk_stats <- hk_master %>%
  st_drop_geometry() %>%
  select(
    total_pop, pop_density, aging_ratio, dependency_ratio,
    n_green_spaces, green_area_per_capita, green_space_pct,
    n_dog_parks, dog_parks_per_100k,
    environmental_score, social_health_score, livability_score
  ) %>%
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

cat("✓ Descriptive statistics calculated\n\n")

# Save statistics table
write_csv(hk_stats, file.path(dir_analysis, "02_descriptive_statistics_hk.csv"))

# Print summary
print(hk_stats)

# ============================================================================
# PART 2: Correlation Analysis - Hong Kong Indicators
# ============================================================================
cat("\n--- Correlation Analysis ---\n")

hk_numeric <- hk_master %>%
  st_drop_geometry() %>%
  select(
    pop_density, aging_ratio, n_green_spaces, green_area_per_capita,
    n_dog_parks, dog_parks_per_100k, environmental_score,
    social_health_score, livability_score
  )

# Calculate correlation matrix
corr_matrix <- cor(hk_numeric, use = "complete.obs")

# Save correlation matrix
write_csv(
  as.data.frame(round(corr_matrix, 3)),
  file.path(dir_analysis, "02_correlation_matrix.csv")
)

# Identify key correlations
strong_corr <- which(abs(corr_matrix) > 0.7 & 
                     abs(corr_matrix) < 1, arr.ind = TRUE)

if (nrow(strong_corr) > 0) {
  cat("Strong correlations identified:\n")
  for (i in 1:nrow(strong_corr)) {
    r1 <- strong_corr[i, 1]
    r2 <- strong_corr[i, 2]
    if (r1 < r2) {
      var1 <- colnames(corr_matrix)[r1]
      var2 <- colnames(corr_matrix)[r2]
      corr_val <- corr_matrix[r1, r2]
      cat(sprintf("  %s <-> %s: %.3f\n", var1, var2, corr_val))
    }
  }
} else {
  cat("No strong correlations found (|r| > 0.7)\n")
}

# Create correlation plot
p_corr <- corrplot(
  corr_matrix,
  method = "circle",
  type = "lower",
  diag = FALSE,
  addCoef.col = "black",
  number.cex = 0.7,
  col = COL2("RdBu", 200)
)

ggsave(
  file.path(dir_figures, "02_correlation_heatmap.png"),
  width = 12, height = 10, dpi = 300
)

cat("✓ Correlation analysis complete\n\n")

# ============================================================================
# PART 3: Distribution Plots - Key Variables
# ============================================================================
cat("--- Creating Distribution Plots ---\n")

# Convert to WGS84 for mapping
hk_wgs <- st_transform(hk_master, wgs84) %>% st_make_valid()

# Function: Create distribution histogram with summary stats
plot_distribution <- function(data, var, title, fill_color = "#2E86AB") {
  ggplot(data, aes(x = .data[[var]])) +
    geom_histogram(fill = fill_color, color = "white", bins = 8, alpha = 0.8) +
    geom_vline(aes(xintercept = mean(.data[[var]], na.rm = TRUE)),
               linetype = "dashed", color = "red", size = 1) +
    geom_vline(aes(xintercept = median(.data[[var]], na.rm = TRUE)),
               linetype = "dotted", color = "blue", size = 1) +
    labs(
      title = title,
      subtitle = sprintf("Mean: %.1f | Median: %.1f",
                        mean(data[[var]], na.rm = TRUE),
                        median(data[[var]], na.rm = TRUE)),
      x = var,
      y = "Number of Districts",
      color = NULL
    ) +
    theme_hk +
    theme(plot.subtitle = element_text(size = 9, color = "grey40"))
}

# Create distribution plots
p_dist_pop <- plot_distribution(hk_master %>% st_drop_geometry(),
                                "pop_density", "Population Density Distribution")
p_dist_age <- plot_distribution(hk_master %>% st_drop_geometry(),
                                "aging_ratio", "Aging Ratio (65+) Distribution")
p_dist_green <- plot_distribution(hk_master %>% st_drop_geometry(),
                                  "green_area_per_capita",
                                  "Green Area Per Capita Distribution",
                                  fill_color = "#06A77D")
p_dist_dogs <- plot_distribution(hk_master %>% st_drop_geometry(),
                                 "dog_parks_per_100k",
                                 "Dog Parks Per 100k Population",
                                 fill_color = "#D62828")

# Combine distribution plots
p_distributions <- (p_dist_pop | p_dist_age) / (p_dist_green | p_dist_dogs)

ggsave(
  file.path(dir_figures, "02_distributions_combined.png"),
  p_distributions,
  width = 14, height = 10, dpi = 300
)

cat("✓ Distribution plots created\n\n")

# ============================================================================
# PART 4: Exploratory Maps - Key Variables
# ============================================================================
cat("--- Creating Exploratory Maps ---\n")

# Function: Create choropleth map
create_choropleth <- function(data, var, title, palette = "viridis") {
  ggplot(data) +
    geom_sf(aes(fill = .data[[var]]), color = "grey40", size = 0.3) +
    scale_fill_viridis_c(option = palette, name = NULL) +
    geom_sf_text(aes(label = substr(name, 1, 3)), 
                 size = 2.5, color = "white", fontface = "bold") +
    labs(title = title) +
    theme_void() +
    theme(
      plot.title = element_text(face = "bold", size = 12, hjust = 0.5),
      legend.position = "right"
    )
}

# Create thematic maps
map_pop_density <- create_choropleth(hk_wgs, "pop_density",
                                    "Population Density (persons/km²)", "B")
map_aging <- create_choropleth(hk_wgs, "aging_ratio",
                              "Aging Ratio (% age 65+)", "C")
map_green <- create_choropleth(hk_wgs, "green_area_per_capita",
                              "Green Area Per Capita (m²/person)", "D")
map_dogs <- create_choropleth(hk_wgs, "dog_parks_per_100k",
                             "Dog Parks Per 100k Population", "A")

# Combine maps
p_maps <- (map_pop_density | map_aging) / (map_green | map_dogs) +
  plot_annotation(
    title = "Hong Kong: Key Demographic & Green Space Indicators",
    theme = theme(plot.title = element_text(face = "bold", size = 14, hjust = 0.5))
  )

ggsave(
  file.path(dir_figures, "02_exploratory_maps.png"),
  p_maps,
  width = 14, height = 12, dpi = 300
)

cat("✓ Exploratory maps created\n\n")

# ============================================================================
# PART 5: Box Plots - Compare Districts
# ============================================================================
cat("--- Creating Box Plots by District Type ---\n")

# Box plot: Environmental scores by density category
p_boxplot <- hk_master %>%
  st_drop_geometry() %>%
  select(district_type, environmental_score, social_health_score, livability_score) %>%
  pivot_longer(
    cols = -district_type,
    names_to = "score_type",
    values_to = "score"
  ) %>%
  ggplot(aes(x = district_type, y = score, fill = score_type)) +
  geom_boxplot(alpha = 0.7, color = "grey40") +
  scale_fill_brewer(palette = "Set2", name = "Score Type") +
  labs(
    title = "Composite Scores by District Density Type",
    x = "District Type (by Population Density)",
    y = "Score (0-100)"
  ) +
  theme_hk +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(
  file.path(dir_figures, "02_boxplot_scores_by_type.png"),
  p_boxplot,
  width = 12, height = 7, dpi = 300
)

cat("✓ Box plots created\n\n")

# ============================================================================
# PART 6: Scatter Plots - Key Relationships
# ============================================================================
cat("--- Creating Scatter Plots ---\n")

# Scatter: Population density vs green space
p_scatter_1 <- hk_master %>%
  st_drop_geometry() %>%
  ggplot(aes(x = log(pop_density), y = green_area_per_capita)) +
  geom_point(aes(color = livability_score, size = total_pop), alpha = 0.7) +
  geom_label_repel(aes(label = substr(name, 1, 3)), size = 3) +
  scale_color_viridis_c(option = "E", name = "Livability") +
  scale_size_continuous(name = "Population") +
  labs(
    title = "Population Density vs Green Space",
    x = "Log Population Density (persons/km²)",
    y = "Green Area Per Capita (m²/person)"
  ) +
  theme_hk

# Scatter: Aging ratio vs environmental score
p_scatter_2 <- hk_master %>%
  st_drop_geometry() %>%
  ggplot(aes(x = aging_ratio, y = environmental_score)) +
  geom_point(aes(color = n_dog_parks, size = total_pop), alpha = 0.7) +
  geom_label_repel(aes(label = substr(name, 1, 3)), size = 3) +
  scale_color_viridis_c(option = "D", name = "Dog Parks") +
  scale_size_continuous(name = "Population") +
  labs(
    title = "Aging Ratio vs Environmental Score",
    x = "Aging Ratio (% age 65+)",
    y = "Environmental Score (0-100)"
  ) +
  theme_hk

# Combine scatter plots
p_scatters <- p_scatter_1 / p_scatter_2

ggsave(
  file.path(dir_figures, "02_scatter_relationships.png"),
  p_scatters,
  width = 14, height = 10, dpi = 300
)

cat("✓ Scatter plots created\n\n")

# ============================================================================
# PART 7: Save Summary Report
# ============================================================================
cat("--- Saving Summary Report ---\n")

summary_report <- sprintf("
=============================================================
EXPLORATORY DATA ANALYSIS REPORT
Hong Kong Urban Green Space & Population Health Analysis
=============================================================

STUDY REGION: %s (%d districts)
ANALYSIS YEAR: %d

KEY FINDINGS:

1. POPULATION CHARACTERISTICS:
   - Total population: %s
   - Mean population density: %.0f persons/km²
   - Aging ratio range: %.1f%% - %.1f%%

2. GREEN SPACE INDICATORS:
   - Mean green area per capita: %.1f m²/person
   - Green space coverage: %.1f%% of total area

3. DOG PARK DISTRIBUTION:
   - Total dog parks in HK: %d
   - Range: %d - %d parks per district

4. LIVABILITY SCORES:
   - Mean livability score: %.1f/100
   - Range: %.1f - %.1f

NEXT STEPS:
- Proceed with spatial analysis (03_green_space_analysis.R)
- Perform statistical modeling (04_population_health_analysis.R)
- Generate global rankings (06_global_ranking_analysis.R)
- Create interactive dashboard (07_interactive_dashboard.R)

=============================================================
",
STUDY_REGION,
nrow(hk_master),
ANALYSIS_YEAR,
format(sum(hk_master$total_pop, na.rm = TRUE), big.mark = ","),
mean(hk_master$pop_density, na.rm = TRUE),
min(hk_master$aging_ratio, na.rm = TRUE),
max(hk_master$aging_ratio, na.rm = TRUE),
mean(hk_master$green_area_per_capita, na.rm = TRUE),
mean(hk_master$green_space_pct, na.rm = TRUE),
sum(hk_master$n_dog_parks, na.rm = TRUE),
min(hk_master$n_dog_parks, na.rm = TRUE),
max(hk_master$n_dog_parks, na.rm = TRUE),
mean(hk_master$livability_score, na.rm = TRUE),
min(hk_master$livability_score, na.rm = TRUE),
max(hk_master$livability_score, na.rm = TRUE)
)

write(summary_report, file.path(dir_analysis, "02_eda_summary_report.txt"))

cat(summary_report)

# ============================================================================
# Session Summary
# ============================================================================
cat("\n===============================================\n")
cat("Exploratory Analysis Complete!\n")
cat("===============================================\n")
cat("Output files created:\n")
cat("  ✓ descriptive_statistics_hk.csv\n")
cat("  ✓ correlation_matrix.csv\n")
cat("  ✓ 4 exploratory visualizations (PNG)\n")
cat("  ✓ EDA summary report (TXT)\n\n")
cat("Next step: Run 03_green_space_analysis.R\n")
cat("===============================================\n\n")
