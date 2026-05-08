# ============================================================================
# 04_population_health_analysis.R
# Population Demographics & Health Infrastructure Analysis
# ============================================================================
# This script creates:
#   1. Population density analysis
#   2. Aging demographics analysis
#   3. Health vulnerability indices
#   4. Spatial epidemiology patterns
# ============================================================================

source("00_setup.R")
load(file.path(dir_analysis, "01_integrated_data.RData"))

cat("\n===============================================\n")
cat("Population Health Analysis Module\n")
cat("===============================================\n\n")

# ============================================================================
# PART 1: Population Demographics Analysis
# ============================================================================
cat("--- Population Demographics Analysis ---\n")

demographics <- hk_master %>%
  st_drop_geometry() %>%
  select(name, total_pop, pop_density, aging_ratio, dependency_ratio, median_age) %>%
  mutate(
    # Population categories
    pop_category = case_when(
      total_pop > 1000000 ~ "Very High (>1M)",
      total_pop > 500000 ~ "High (500k-1M)",
      total_pop > 250000 ~ "Medium (250k-500k)",
      TRUE ~ "Low (<250k)"
    ),
    
    # Aging severity categories
    aging_category = case_when(
      aging_ratio > 25 ~ "Highly Aged (>25%)",
      aging_ratio > 20 ~ "Moderately Aged (20-25%)",
      aging_ratio > 15 ~ "Aging (15-20%)",
      TRUE ~ "Young (<15%)"
    ),
    
    # Health vulnerability score
    vulnerability_score = (
      standardize_to_100(log(pop_density + 1)) * 0.3 +      # Population pressure
      standardize_to_100(aging_ratio) * 0.4 +               # Aging burden
      standardize_to_100(dependency_ratio) * 0.3             # Dependency ratio
    ),
    
    # Social support needs score
    social_support_needs = case_when(
      aging_ratio > 22 & dependency_ratio > 40 ~ "Critical",
      aging_ratio > 18 & dependency_ratio > 35 ~ "High",
      aging_ratio > 15 & dependency_ratio > 30 ~ "Moderate",
      TRUE ~ "Low"
    )
  ) %>%
  arrange(desc(vulnerability_score))

write_csv(demographics, 
         file.path(dir_analysis, "04_population_demographics.csv"))

cat("✓ Population demographics analyzed\n\n")
print(head(demographics, 10))
cat("\n")

# ============================================================================
# PART 2: Aging Index Analysis
# ============================================================================
cat("--- Aging Index & Dependency Analysis ---\n")

aging_analysis <- hk_master %>%
  st_drop_geometry() %>%
  select(name, aging_ratio, median_age, dependency_ratio, total_pop) %>%
  mutate(
    # Old-age dependency ratio (65+ / working age 15-64)
    old_age_dependency = aging_ratio * (100 - aging_ratio - 15) / 
                         (100 - aging_ratio),
    
    # Youth dependency ratio (0-14 / working age)
    youth_dependency = 15 * (100 - aging_ratio - 15) / 
                      (100 - aging_ratio),
    
    # Total support burden
    total_support_burden = old_age_dependency + youth_dependency,
    
    # Aging index (65+ / 0-14)
    aging_index = aging_ratio / 15,
    
    # Categorize aging status
    aging_status = case_when(
      aging_index > 2 ~ "Post-Aged Society",
      aging_index > 1 ~ "Aged Society",
      aging_index > 0.5 ~ "Aging Society",
      TRUE ~ "Young Society"
    )
  ) %>%
  arrange(desc(aging_index))

write_csv(aging_analysis,
         file.path(dir_analysis, "04_aging_index_analysis.csv"))

cat("✓ Aging analysis complete\n")
cat("\nAging status distribution:\n")
print(table(aging_analysis$aging_status))
cat("\n")

# ============================================================================
# PART 3: Healthcare Need Assessment
# ============================================================================
cat("--- Healthcare Need Assessment ---\n")

healthcare_needs <- hk_master %>%
  st_drop_geometry() %>%
  select(name, total_pop, aging_ratio, dependency_ratio) %>%
  mutate(
    # Estimated healthcare demand (simplified model)
    elderly_population_65plus = total_pop * (aging_ratio / 100),
    young_dependent = total_pop * 0.15,
    
    # Healthcare resource need indices
    geriatric_care_index = elderly_population_65plus / 1000,  # per 1000 population
    pediatric_care_index = young_dependent / 1000,
    total_care_index = (elderly_population_65plus + young_dependent) / 1000,
    
    # Healthcare vulnerability score (0-100)
    healthcare_vulnerability = case_when(
      total_care_index > 400 ~ 95,
      total_care_index > 350 ~ 85,
      total_care_index > 300 ~ 75,
      total_care_index > 250 ~ 65,
      total_care_index > 200 ~ 50,
      TRUE ~ 30
    )
  ) %>%
  arrange(desc(healthcare_vulnerability))

write_csv(healthcare_needs,
         file.path(dir_analysis, "04_healthcare_needs.csv"))

cat("✓ Healthcare need assessment complete\n")
cat(sprintf("Districts with critical healthcare needs (>85 score): %d\n",
            sum(healthcare_needs$healthcare_vulnerability >= 85)))
cat("\n")

# ============================================================================
# PART 4: Green Space - Health Benefit Analysis
# ============================================================================
cat("--- Green Space & Health Benefit Analysis ---\n")

load(file.path(dir_analysis, "03_green_space_results.RData"))

health_benefit <- hk_master %>%
  st_drop_geometry() %>%
  select(name, aging_ratio, dependency_ratio, pop_density) %>%
  left_join(equity_analysis %>% select(name, green_area_per_capita, 
                                       green_space_equity_score),
           by = "name") %>%
  mutate(
    # Health-adjusted green space score
    # High-priority areas (aging + high density) benefit more from green space
    health_benefit_potential = (
      standardize_to_100(aging_ratio) * 0.4 +           # Elderly need recreation
      standardize_to_100(log(pop_density + 1)) * 0.3 +  # Urban congestion
      (100 - standardize_to_100(pop_density)) * 0.3     # Favor lower density improvements
    ),
    
    # Green space adequacy for health needs
    green_space_health_adequacy = case_when(
      green_area_per_capita >= 15 & health_benefit_potential < 50 ~ "Exceeds Need",
      green_area_per_capita >= 12 & health_benefit_potential < 65 ~ "Adequate",
      green_area_per_capita >= 8 & health_benefit_potential < 75 ~ "Moderate Gap",
      green_area_per_capita >= 5 ~ "Significant Gap",
      TRUE ~ "Critical Deficit"
    ),
    
    # Priority ranking for green space investment
    green_investment_priority = case_when(
      health_benefit_potential > 75 & green_area_per_capita < 8 ~ "Urgent",
      health_benefit_potential > 65 & green_area_per_capita < 10 ~ "High",
      health_benefit_potential > 50 & green_area_per_capita < 12 ~ "Moderate",
      TRUE ~ "Low"
    )
  ) %>%
  arrange(desc(health_benefit_potential))

write_csv(health_benefit,
         file.path(dir_analysis, "04_green_space_health_benefit.csv"))

cat("✓ Green space-health benefit analysis complete\n")
cat("\nGreen space investment priorities:\n")
print(table(health_benefit$green_investment_priority))
cat("\n")

# ============================================================================
# PART 5: Visualization - Demographics Maps
# ============================================================================
cat("--- Creating Population Health Visualizations ---\n")

hk_wgs <- st_transform(hk_master, wgs84) %>% st_make_valid()

# Map 1: Aging ratio
map_aging <- ggplot(hk_wgs) +
  geom_sf(aes(fill = aging_ratio), color = "grey40", size = 0.3) +
  scale_fill_viridis_c(option = "C", name = "Aging %") +
  geom_sf_text(aes(label = substr(name, 1, 3)), size = 2.5, color = "white", fontface = "bold") +
  labs(title = "Aging Ratio (% 65+)") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 12, hjust = 0.5))

# Map 2: Dependency ratio
map_dependency <- ggplot(hk_wgs) +
  geom_sf(aes(fill = dependency_ratio), color = "grey40", size = 0.3) +
  scale_fill_viridis_c(option = "B", name = "Dependency %") +
  geom_sf_text(aes(label = substr(name, 1, 3)), size = 2.5, color = "white", fontface = "bold") +
  labs(title = "Dependency Ratio (%)") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 12, hjust = 0.5))

# Map 3: Healthcare vulnerability
hk_healthcare <- hk_wgs %>%
  left_join(healthcare_needs %>% select(name, healthcare_vulnerability),
           by = "name")

map_healthcare <- ggplot(hk_healthcare) +
  geom_sf(aes(fill = healthcare_vulnerability), color = "grey40", size = 0.3) +
  scale_fill_viridis_c(option = "A", name = "Vulnerability") +
  geom_sf_text(aes(label = substr(name, 1, 3)), size = 2.5, color = "white", fontface = "bold") +
  labs(title = "Healthcare Vulnerability Index") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 12, hjust = 0.5))

# Combine maps
p_health_maps <- (map_aging | map_dependency | map_healthcare) +
  plot_annotation(
    title = "Hong Kong: Population Health & Demographic Indicators",
    theme = theme(plot.title = element_text(face = "bold", size = 14, hjust = 0.5))
  )

ggsave(
  file.path(dir_figures, "04_population_health_maps.png"),
  p_health_maps,
  width = 16, height = 6, dpi = 300
)

cat("✓ Population health maps created\n\n")

# ============================================================================
# PART 6: Scatter Plot - Aging vs Green Space
# ============================================================================
cat("--- Creating Relationship Plots ---\n")

health_scatter_data <- hk_wgs %>%
  left_join(health_benefit %>% select(name, health_benefit_potential, 
                                     green_investment_priority),
           by = "name")

p_health_scatter <- health_scatter_data %>%
  st_drop_geometry() %>%
  ggplot(aes(x = aging_ratio, y = green_area_per_capita)) +
  geom_point(aes(color = green_investment_priority, size = total_pop), alpha = 0.7) +
  geom_label_repel(aes(label = substr(name, 1, 3)), size = 3) +
  scale_color_manual(
    values = c("Urgent" = "#FF6B6B", "High" = "#FFA500",
              "Moderate" = "#FFD700", "Low" = "#90EE90"),
    name = "Investment Priority"
  ) +
  scale_size_continuous(name = "Population") +
  labs(
    title = "Aging Population vs Green Space Availability",
    subtitle = "Investment priority based on health benefit potential",
    x = "Aging Ratio (% age 65+)",
    y = "Green Area Per Capita (m²/person)"
  ) +
  theme_hk

ggsave(
  file.path(dir_figures, "04_aging_green_relationship.png"),
  p_health_scatter,
  width = 12, height = 8, dpi = 300
)

cat("✓ Relationship plots created\n\n")

# ============================================================================
# PART 7: Bar Plot - Healthcare Vulnerability Categories
# ============================================================================
cat("--- Creating Healthcare Vulnerability Plot ---\n")

vulnerability_summary <- demographics %>%
  group_by(social_support_needs) %>%
  summarise(
    n_districts = n(),
    avg_aging_ratio = mean(aging_ratio),
    avg_dependency = mean(dependency_ratio),
    total_population = sum(total_pop),
    .groups = "drop"
  ) %>%
  mutate(social_support_needs = factor(social_support_needs,
                                       levels = c("Critical", "High", "Moderate", "Low")))

p_vulnerability_bar <- vulnerability_summary %>%
  ggplot(aes(x = social_support_needs, y = n_districts, fill = social_support_needs)) +
  geom_col(color = "white", size = 1) +
  scale_fill_manual(
    values = c("Critical" = "#FF6B6B", "High" = "#FFA500",
              "Moderate" = "#FFD700", "Low" = "#90EE90"),
    guide = "none"
  ) +
  geom_text(aes(label = n_districts), vjust = -0.5, fontface = "bold") +
  labs(
    title = "District Distribution by Social Support Needs",
    x = "Social Support Needs Category",
    y = "Number of Districts"
  ) +
  theme_hk +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(
  file.path(dir_figures, "04_social_support_needs.png"),
  p_vulnerability_bar,
  width = 10, height = 6, dpi = 300
)

cat("✓ Healthcare vulnerability plot created\n\n")

# ============================================================================
# PART 8: Save Results
# ============================================================================
cat("--- Saving Analysis Results ---\n")

save(
  demographics, aging_analysis, healthcare_needs, health_benefit,
  file = file.path(dir_analysis, "04_population_health_results.RData")
)

# ============================================================================
# Summary Report
# ============================================================================
cat("\n===============================================\n")
cat("Population Health Analysis Complete!\n")
cat("===============================================\n\n")

summary_text <- sprintf(
"POPULATION HEALTH ANALYSIS SUMMARY

DEMOGRAPHIC OVERVIEW:
- Total HK population: %s
- Mean aging ratio: %.1f%%
- Districts with >20%% aging ratio: %d
- Mean dependency ratio: %.1f%%

AGING STATUS:
- Highly aged districts (>25%%): %d
- Moderately aged districts (20-25%%): %d
- Aging districts (15-20%%): %d
- Young districts (<15%%): %d

HEALTHCARE NEEDS:
- Critical healthcare needs: %d districts
- High healthcare needs: %d districts
- Moderate healthcare needs: %d districts
- Low healthcare needs: %d districts

GREEN SPACE INVESTMENT PRIORITY:
- Urgent intervention needed: %d districts
- High priority: %d districts
- Moderate priority: %d districts
- Low priority: %d districts

KEY FINDINGS:
- Highest vulnerability district: %s (score: %.1f)
- Lowest vulnerability district: %s (score: %.1f)
- Average health benefit potential from green space: %.1f

RECOMMENDATIONS:
- Focus green space investment on: %s
- Monitor elderly care infrastructure in: %s
- Coordinate health & environmental planning in: %s

",

format(sum(hk_master$total_pop, na.rm = TRUE), big.mark = ","),
mean(demographics$aging_ratio),
sum(demographics$aging_ratio > 20),
mean(demographics$dependency_ratio),

sum(demographics$aging_category == "Highly Aged (>25%)"),
sum(demographics$aging_category == "Moderately Aged (20-25%)"),
sum(demographics$aging_category == "Aging (15-20%)"),
sum(demographics$aging_category == "Young (<15%)"),

sum(healthcare_needs$healthcare_vulnerability >= 85),
sum(healthcare_needs$healthcare_vulnerability >= 70 & healthcare_needs$healthcare_vulnerability < 85),
sum(healthcare_needs$healthcare_vulnerability >= 50 & healthcare_needs$healthcare_vulnerability < 70),
sum(healthcare_needs$healthcare_vulnerability < 50),

sum(health_benefit$green_investment_priority == "Urgent"),
sum(health_benefit$green_investment_priority == "High"),
sum(health_benefit$green_investment_priority == "Moderate"),
sum(health_benefit$green_investment_priority == "Low"),

demographics$name[1], demographics$vulnerability_score[1],
demographics$name[nrow(demographics)], demographics$vulnerability_score[nrow(demographics)],
mean(health_benefit$health_benefit_potential),

paste(head(health_benefit$name[health_benefit$green_investment_priority == "Urgent"], 3), collapse = ", "),
paste(head(demographics$name[demographics$social_support_needs == "Critical"], 3), collapse = ", "),
paste(head(demographics$name[demographics$aging_ratio > 20], 3), collapse = ", ")
)

write(summary_text, file.path(dir_analysis, "04_population_health_summary.txt"))
cat(summary_text)

cat("Output files:\n")
cat("  ✓ population_demographics.csv\n")
cat("  ✓ aging_index_analysis.csv\n")
cat("  ✓ healthcare_needs.csv\n")
cat("  ✓ green_space_health_benefit.csv\n")
cat("  ✓ Multiple visualization outputs\n")
cat("  ✓ Analysis summary report\n\n")
cat("Next step: Run 05_global_ranking_analysis.R\n")
cat("===============================================\n\n")
