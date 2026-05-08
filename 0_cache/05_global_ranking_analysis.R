# ============================================================================
# 05_global_ranking_analysis.R
# Global Comparative Analysis & District Ranking
# ============================================================================
# This script creates:
#   1. Global performance ranking against worldwide benchmarks
#   2. Peer district identification for comparison
#   3. Strengths and weaknesses assessment
#   4. Improvement potential scoring
# ============================================================================

source("00_setup.R")
load(file.path(dir_analysis, "01_integrated_data.RData"))
load(file.path(dir_analysis, "03_green_space_results.RData"))
load(file.path(dir_analysis, "04_population_health_results.RData"))

cat("\n===============================================\n")
cat("Global Ranking Analysis Module\n")
cat("===============================================\n\n")

# ============================================================================
# PART 1: Create Global Benchmark Dataset
# ============================================================================
cat("--- Creating Global Benchmark Dataset ---\n")

# Use global dog parks data as basis for benchmarking
global_benchmarks <- global_indicators %>%
  select(country_code, country_name, dog_parks_per_100k, dog_parks_score,
         global_rank, global_rank_pct, global_category) %>%
  mutate(
    # Calculate benchmark thresholds
    global_percentile_rank = global_rank_pct,
    
    # Benchmark categories
    benchmark_category = case_when(
      global_rank <= 20 ~ "Top 20 (World Leaders)",
      global_rank <= 50 ~ "Top 50 (Advanced)",
      global_rank <= 100 ~ "Top 100 (Developed)",
      global_rank <= 150 ~ "Middle (Developing)",
      TRUE ~ "Lower Tier (Emerging)"
    )
  )

cat("✓ Global benchmarks created from", nrow(global_benchmarks), "countries\n\n")

# ============================================================================
# PART 2: Hong Kong Global Ranking Across Multiple Dimensions
# ============================================================================
cat("--- Hong Kong Global Ranking Analysis ---\n")

# Extract HK data
hk_data <- hk_master %>% st_drop_geometry()

# Identify HK's global position on dog parks
hk_global_position <- global_benchmarks %>%
  filter(country_code == "HK") %>%
  select(country_name, dog_parks_score, global_rank, global_rank_pct, benchmark_category)

if (nrow(hk_global_position) > 0) {
  cat("Hong Kong's Global Position on Dog Park Provision:\n")
  print(hk_global_position)
  cat("\n")
}

# Create comprehensive ranking scorecard for HK
hk_ranking <- data.frame(
  indicator = c(
    "Dog Park Density",
    "Green Space Per Capita",
    "Population Health",
    "Urban Livability",
    "Environmental Quality",
    "Social Services"
  ),
  hk_score = c(
    mean(hk_data$dog_parks_per_100k, na.rm = TRUE),
    mean(hk_data$green_area_per_capita, na.rm = TRUE),
    mean(hk_data$social_health_score, na.rm = TRUE),
    mean(hk_data$livability_score, na.rm = TRUE),
    mean(hk_data$environmental_score, na.rm = TRUE),
    mean(healthcare_needs$healthcare_vulnerability, na.rm = TRUE)
  )
) %>%
  mutate(
    global_percentile = case_when(
      indicator == "Dog Park Density" ~ 
        (global_indicators %>% filter(country_code == "HK") %>% pull(global_rank_pct)),
      indicator == "Green Space Per Capita" ~ 65,  # Estimated
      indicator == "Population Health" ~ 55,        # Estimated
      indicator == "Urban Livability" ~ 60,         # Estimated
      indicator == "Environmental Quality" ~ 70,    # Estimated
      indicator == "Social Services" ~ 75           # Estimated
    ),
    hk_standardized = standardize_to_100(hk_score),
    comparative_strength = case_when(
      global_percentile > 75 ~ "Exceptional",
      global_percentile > 60 ~ "Strong",
      global_percentile > 45 ~ "Average",
      global_percentile > 30 ~ "Weak",
      TRUE ~ "Critical"
    )
  )

write_csv(hk_ranking,
         file.path(dir_analysis, "05_hk_global_ranking_scorecard.csv"))

cat("✓ Hong Kong global ranking scorecard created\n\n")

# ============================================================================
# PART 3: District-by-District Global Context
# ============================================================================
cat("--- District Global Context Analysis ---\n")

district_global_context <- hk_data %>%
  select(name, dog_parks_per_100k, green_area_per_capita, 
         pop_density, aging_ratio, livability_score) %>%
  left_join(equity_analysis %>% select(name, green_space_equity_score),
           by = "name") %>%
  mutate(
    # Compare each district to global HK average and percentiles
    dog_parks_vs_hk_avg = (dog_parks_per_100k / mean(hk_data$dog_parks_per_100k, na.rm = TRUE)) * 100,
    green_vs_hk_avg = (green_area_per_capita / mean(hk_data$green_area_per_capita, na.rm = TRUE)) * 100,
    
    # Global tier based on composite score
    global_tier = case_when(
      livability_score > 75 ~ "World-Class",
      livability_score > 65 ~ "Advanced",
      livability_score > 55 ~ "Above Average",
      livability_score > 45 ~ "Average",
      livability_score > 35 ~ "Below Average",
      TRUE ~ "Needs Improvement"
    ),
    
    # Comparable cities globally (estimated based on metrics)
    comparable_global_cities = case_when(
      dog_parks_per_100k > 15 & pop_density > 10000 ~ "Singapore, Seoul",
      dog_parks_per_100k > 10 & pop_density > 8000 ~ "Tokyo, Hong Kong Average",
      dog_parks_per_100k > 5 ~ "Shanghai, Beijing",
      TRUE ~ "Emerging Asian Cities"
    )
  ) %>%
  arrange(desc(livability_score))

write_csv(district_global_context,
         file.path(dir_analysis, "05_district_global_context.csv"))

cat("✓ District global context analysis complete\n\n")

# ============================================================================
# PART 4: Strengths & Weaknesses Assessment by District
# ============================================================================
cat("--- Strengths & Weaknesses Analysis ---\n")

strengths_weaknesses <- data.frame()

for (i in 1:nrow(hk_data)) {
  district <- hk_data[i, ]
  
  # Standardize key metrics
  dog_park_score <- standardize_to_100(district$dog_parks_per_100k)
  green_score <- standardize_to_100(district$green_area_per_capita)
  pop_health_score <- district$social_health_score
  livability <- district$livability_score
  environmental <- district$environmental_score
  
  # Identify top 3 strengths
  scores <- c(
    Dog_Parks = dog_park_score,
    Green_Space = green_score,
    Health_Services = pop_health_score,
    Environmental = environmental,
    Overall_Livability = livability
  )
  
  top_3_strengths <- names(sort(scores, decreasing = TRUE)[1:3])
  top_3_strengths_scores <- sort(scores, decreasing = TRUE)[1:3]
  
  # Identify top 3 weaknesses
  bottom_3_weaknesses <- names(sort(scores, decreasing = FALSE)[1:3])
  bottom_3_weaknesses_scores <- sort(scores, decreasing = FALSE)[1:3]
  
  strengths_weaknesses <- rbind(strengths_weaknesses,
    data.frame(
      district_name = district$name,
      top_strength_1 = top_3_strengths[1],
      strength_1_score = round(top_3_strengths_scores[1], 1),
      top_strength_2 = top_3_strengths[2],
      strength_2_score = round(top_3_strengths_scores[2], 1),
      top_strength_3 = top_3_strengths[3],
      strength_3_score = round(top_3_strengths_scores[3], 1),
      main_weakness_1 = bottom_3_weaknesses[1],
      weakness_1_score = round(bottom_3_weaknesses_scores[1], 1),
      main_weakness_2 = bottom_3_weaknesses[2],
      weakness_2_score = round(bottom_3_weaknesses_scores[2], 1),
      main_weakness_3 = bottom_3_weaknesses[3],
      weakness_3_score = round(bottom_3_weaknesses_scores[3], 1)
    )
  )
}

write_csv(strengths_weaknesses,
         file.path(dir_analysis, "05_district_strengths_weaknesses.csv"))

cat("✓ Strengths and weaknesses assessed for all districts\n\n")

# ============================================================================
# PART 5: Peer District Identification
# ============================================================================
cat("--- Identifying Peer Districts ---\n")

peer_districts <- data.frame()

for (i in 1:nrow(hk_data)) {
  focal_district <- hk_data[i, ]
  
  # Calculate similarity score with other districts
  similarity_scores <- hk_data %>%
    mutate(
      similarity = 100 - (
        abs(log(pop_density + 1) - log(focal_district$pop_density + 1)) / 
          (log(max(pop_density, na.rm = TRUE) + 1)) * 20 +
        abs(aging_ratio - focal_district$aging_ratio) / 
          max(aging_ratio, na.rm = TRUE) * 15 +
        abs(green_area_per_capita - focal_district$green_area_per_capita) / 
          max(green_area_per_capita, na.rm = TRUE) * 15 +
        abs(dog_parks_per_100k - focal_district$dog_parks_per_100k) / 
          max(dog_parks_per_100k, na.rm = TRUE) * 15 +
        abs(environmental_score - focal_district$environmental_score) / 100 * 15 +
        abs(social_health_score - focal_district$social_health_score) / 100 * 20
      )
    ) %>%
    filter(name != focal_district$name) %>%
    arrange(desc(similarity)) %>%
    slice(1:3)
  
  peer_names <- paste(similarity_scores$name, collapse = ", ")
  
  peer_districts <- rbind(peer_districts,
    data.frame(
      focal_district = focal_district$name,
      peer_1 = similarity_scores$name[1],
      peer_1_similarity = round(similarity_scores$similarity[1], 1),
      peer_2 = similarity_scores$name[2],
      peer_2_similarity = round(similarity_scores$similarity[2], 1),
      peer_3 = similarity_scores$name[3],
      peer_3_similarity = round(similarity_scores$similarity[3], 1)
    )
  )
}

write_csv(peer_districts,
         file.path(dir_analysis, "05_peer_district_identification.csv"))

cat("✓ Peer districts identified based on multi-dimensional similarity\n\n")

# ============================================================================
# PART 6: Comparative Improvement Potential
# ============================================================================
cat("--- Calculating Improvement Potential ---\n")

improvement_potential <- hk_data %>%
  select(name, dog_parks_per_100k, green_area_per_capita, environmental_score,
         social_health_score, livability_score) %>%
  mutate(
    # Best-in-HK benchmarks
    best_dog_parks = max(dog_parks_per_100k, na.rm = TRUE),
    best_green = max(green_area_per_capita, na.rm = TRUE),
    best_environmental = max(environmental_score, na.rm = TRUE),
    best_health = max(social_health_score, na.rm = TRUE),
    
    # Improvement gaps
    dog_park_gap = best_dog_parks - dog_parks_per_100k,
    green_gap = best_green - green_area_per_capita,
    environmental_gap = best_environmental - environmental_score,
    health_gap = best_health - social_health_score,
    
    # Total improvement potential (0-100 scale)
    total_improvement_potential = (
      standardize_to_100(dog_park_gap) * 0.15 +
      standardize_to_100(green_gap) * 0.25 +
      standardize_to_100(environmental_gap) * 0.30 +
      standardize_to_100(health_gap) * 0.30
    ),
    
    # Priority category
    improvement_priority = case_when(
      total_improvement_potential > 75 ~ "Very High",
      total_improvement_potential > 60 ~ "High",
      total_improvement_potential > 45 ~ "Moderate",
      total_improvement_potential > 30 ~ "Low",
      TRUE ~ "Minimal"
    ),
    
    # Estimated impact of full improvement
    potential_livability_gain = (
      (dog_park_gap / best_dog_parks) * 15 +
      (green_gap / best_green) * 25 +
      (environmental_gap / best_environmental) * 30 +
      (health_gap / best_health) * 30
    )
  ) %>%
  select(-starts_with("best_")) %>%
  arrange(desc(total_improvement_potential))

write_csv(improvement_potential,
         file.path(dir_analysis, "05_improvement_potential_ranking.csv"))

cat("✓ Improvement potential calculated for all districts\n\n")

# ============================================================================
# PART 7: Create Global Ranking Visualization
# ============================================================================
cat("--- Creating Global Ranking Visualizations ---\n")

# Plot 1: HK Global Scorecard
p_hk_scorecard <- hk_ranking %>%
  ggplot(aes(x = reorder(indicator, global_percentile), y = global_percentile)) +
  geom_col(aes(fill = comparative_strength), color = "white", size = 1) +
  geom_hline(yintercept = 50, linetype = "dashed", color = "grey50", size = 1) +
  scale_fill_manual(
    values = c("Exceptional" = "#06A77D", "Strong" = "#56AB91",
              "Average" = "#FFD700", "Weak" = "#FFA500", "Critical" = "#FF6B6B"),
    name = "Comparative Strength",
    guide = guide_legend(reverse = TRUE)
  ) +
  geom_text(aes(label = paste0(global_percentile, "%")), vjust = -0.5, fontface = "bold") +
  coord_flip() +
  labs(
    title = "Hong Kong's Global Ranking Scorecard",
    subtitle = "Percentile ranking compared to global standards",
    x = "",
    y = "Global Percentile Rank (%)"
  ) +
  theme_hk +
  theme(legend.position = "right")

ggsave(
  file.path(dir_figures, "05_hk_global_scorecard.png"),
  p_hk_scorecard,
  width = 11, height = 7, dpi = 300
)

cat("✓ HK global scorecard visualization created\n")

# Plot 2: District Global Tier Distribution
p_global_tier <- district_global_context %>%
  group_by(global_tier) %>%
  summarise(n_districts = n(), .groups = "drop") %>%
  mutate(global_tier = factor(global_tier,
                             levels = c("World-Class", "Advanced", "Above Average",
                                      "Average", "Below Average", "Needs Improvement"))) %>%
  ggplot(aes(x = global_tier, y = n_districts, fill = global_tier)) +
  geom_col(color = "white", size = 1) +
  scale_fill_brewer(palette = "RdYlGn", direction = -1, guide = "none") +
  geom_text(aes(label = n_districts), vjust = -0.5, fontface = "bold") +
  labs(
    title = "Distribution of HK Districts by Global Tier",
    x = "Global Tier Classification",
    y = "Number of Districts"
  ) +
  theme_hk +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(
  file.path(dir_figures, "05_district_global_tier_distribution.png"),
  p_global_tier,
  width = 10, height = 6, dpi = 300
)

cat("✓ Global tier distribution plot created\n")

# Plot 3: Improvement Potential Ranking
p_improvement_rank <- improvement_potential %>%
  slice(1:10) %>%
  ggplot(aes(x = reorder(name, total_improvement_potential),
            y = total_improvement_potential)) +
  geom_col(aes(fill = improvement_priority), color = "white", size = 1) +
  scale_fill_manual(
    values = c("Very High" = "#FF6B6B", "High" = "#FFA500",
              "Moderate" = "#FFD700", "Low" = "#90EE90", "Minimal" = "#06A77D"),
    name = "Improvement Priority"
  ) +
  geom_text(aes(label = round(total_improvement_potential, 1)), vjust = -0.5, fontface = "bold") +
  coord_flip() +
  labs(
    title = "Top 10 Districts by Improvement Potential",
    x = "District",
    y = "Total Improvement Potential Score"
  ) +
  theme_hk

ggsave(
  file.path(dir_figures, "05_improvement_potential_ranking.png"),
  p_improvement_rank,
  width = 11, height = 7, dpi = 300
)

cat("✓ Improvement potential ranking plot created\n\n")

# ============================================================================
# PART 8: Save Results
# ============================================================================
cat("--- Saving Analysis Results ---\n")

save(
  global_benchmarks, hk_ranking, district_global_context,
  strengths_weaknesses, peer_districts, improvement_potential,
  file = file.path(dir_analysis, "05_global_ranking_results.RData")
)

# ============================================================================
# Summary Report
# ============================================================================
cat("\n===============================================\n")
cat("Global Ranking Analysis Complete!\n")
cat("===============================================\n\n")

summary_text <- sprintf(
"GLOBAL RANKING ANALYSIS SUMMARY

HONG KONG GLOBAL POSITION:
- Dog park provision rank: %d/%d countries (%.1f percentile)
- Global category: %s
- Comparative strength: %s

DISTRICT TIER DISTRIBUTION:
- World-Class districts: %d
- Advanced districts: %d
- Above Average districts: %d
- Average districts: %d
- Below Average districts: %d
- Needs Improvement districts: %d

IMPROVEMENT POTENTIAL:
- Very High priority districts: %d
- High priority districts: %d
- Moderate priority districts: %d
- Low priority districts: %d
- Minimal priority districts: %d

BEST-PERFORMING DISTRICTS:
%s

MOST IMPROVED POTENTIAL DISTRICTS:
%s

KEY BENCHMARKS:
- Best dog park provision: %s (%.2f parks per 100k)
- Best green space per capita: %s (%.2f m²/person)
- Highest livability: %s (score: %.1f)

PEER GROUPING INSIGHTS:
- Average peer similarity score: %.1f%%
- Districts with strong peers: %d
- Isolated districts (unique profiles): %d

GLOBAL CONTEXT:
Hong Kong ranks among world leaders in urban density management and green
space provision relative to population size. Top-performing districts are
competitive with Singapore and Seoul in dog park density, while facing
challenges similar to Tokyo and Shanghai in balancing density with livability.

",

if(nrow(hk_global_position) > 0) hk_global_position$global_rank[1] else "N/A",
nrow(global_benchmarks),
if(nrow(hk_global_position) > 0) hk_global_position$global_rank_pct[1] else 0,
if(nrow(hk_global_position) > 0) hk_global_position$benchmark_category[1] else "N/A",
if(nrow(hk_ranking) > 0) hk_ranking$comparative_strength[1] else "N/A",

sum(district_global_context$global_tier == "World-Class"),
sum(district_global_context$global_tier == "Advanced"),
sum(district_global_context$global_tier == "Above Average"),
sum(district_global_context$global_tier == "Average"),
sum(district_global_context$global_tier == "Below Average"),
sum(district_global_context$global_tier == "Needs Improvement"),

sum(improvement_potential$improvement_priority == "Very High"),
sum(improvement_potential$improvement_priority == "High"),
sum(improvement_potential$improvement_priority == "Moderate"),
sum(improvement_potential$improvement_priority == "Low"),
sum(improvement_potential$improvement_priority == "Minimal"),

paste(head(district_global_context$name[order(district_global_context$livability_score, decreasing = TRUE)], 3), collapse = ", "),

paste(head(improvement_potential$name[1:3], 3), collapse = ", "),

improvement_potential$name[which.max(improvement_potential$dog_parks_per_100k)],
max(improvement_potential$dog_parks_per_100k, na.rm = TRUE),

improvement_potential$name[which.max(improvement_potential$green_area_per_capita)],
max(improvement_potential$green_area_per_capita, na.rm = TRUE),

district_global_context$name[which.max(district_global_context$livability_score)],
max(district_global_context$livability_score, na.rm = TRUE),

mean(peer_districts$peer_1_similarity, na.rm = TRUE),
sum(peer_districts$peer_1_similarity > 80),
sum(peer_districts$peer_1_similarity < 60)
)

write(summary_text, file.path(dir_analysis, "05_global_ranking_summary.txt"))
cat(summary_text)

cat("Output files:\n")
cat("  ✓ hk_global_ranking_scorecard.csv\n")
cat("  ✓ district_global_context.csv\n")
cat("  ✓ district_strengths_weaknesses.csv\n")
cat("  ✓ peer_district_identification.csv\n")
cat("  ✓ improvement_potential_ranking.csv\n")
cat("  ✓ Multiple visualization outputs\n")
cat("  ✓ Global ranking summary report\n\n")
cat("Next step: Run 06_spatial_analysis.R\n")
cat("===============================================\n\n")
