# ============================================================================
# 03_green_space_analysis.R
# Green Space Accessibility & Landscape Analysis
# ============================================================================
# This script creates:
#   1. Green space accessibility analysis (distance/catchment area)
#   2. Landscape fragmentation metrics
#   3. Green space equity analysis (per capita analysis)
#   4. Spatial hot spot detection
# ============================================================================

source("00_setup.R")
load(file.path(dir_analysis, "01_integrated_data.RData"))

cat("\n===============================================\n")
cat("Green Space Analysis Module\n")
cat("===============================================\n\n")

# ============================================================================
# PART 1: Green Space Accessibility Analysis
# ============================================================================
cat("--- Green Space Accessibility Analysis ---\n")

# Project to HK1980 for distance calculations in meters
green_hk <- st_transform(green_spaces_osm, hk_crs) %>% st_make_valid()
districts_hk <- st_transform(hk_districts, hk_crs) %>% st_make_valid()

# Calculate accessibility metrics for each district
accessibility_results <- data.frame()

for (i in 1:nrow(districts_hk)) {
  district <- districts_hk[i, ]
  district_name <- district$name
  
  # Distance to nearest green space
  dist_to_nearest <- min(st_distance(district, green_hk), na.rm = TRUE)
  
  # Number of green spaces within various distances
  green_within_500m <- length(st_intersects(
    st_buffer(district, 500),
    green_hk,
    sparse = FALSE
  )[1, which(st_intersects(st_buffer(district, 500), green_hk, sparse = FALSE)[1, ])])
  
  green_within_1km <- length(st_intersects(
    st_buffer(district, 1000),
    green_hk,
    sparse = FALSE
  )[1, which(st_intersects(st_buffer(district, 1000), green_hk, sparse = FALSE)[1, ])])
  
  # Green space coverage percentage
  green_in_district <- st_intersection(green_hk, district)
  green_coverage_pct <- ifelse(st_area(district) > 0,
                              sum(st_area(green_in_district)) / st_area(district) * 100,
                              0)
  
  accessibility_results <- rbind(accessibility_results,
    data.frame(
      district_name = district_name,
      dist_nearest_green_m = as.numeric(dist_to_nearest),
      n_green_within_500m = green_within_500m,
      n_green_within_1km = green_within_1km,
      green_coverage_pct = as.numeric(green_coverage_pct)
    )
  )
}

cat("✓ Accessibility metrics calculated for", nrow(accessibility_results), "districts\n\n")

# ============================================================================
# PART 2: Green Space Equity Analysis
# ============================================================================
cat("--- Green Space Equity Analysis ---\n")

equity_analysis <- hk_master %>%
  st_drop_geometry() %>%
  select(name, total_pop, pop_density, green_area_per_capita, 
         aging_ratio, n_dog_parks) %>%
  left_join(accessibility_results, by = c("name" = "district_name")) %>%
  mutate(
    # Equity indicators
    green_space_equity_score = ifelse(pop_density > 0,
                                     (green_area_per_capita / mean(green_area_per_capita, na.rm = TRUE)) * 100,
                                     0),
    accessibility_score = ifelse(dist_nearest_green_m > 0,
                                (1 - (dist_nearest_green_m / max(dist_nearest_green_m, na.rm = TRUE))) * 100,
                                0),
    
    # Equity category based on multiple factors
    equity_category = case_when(
      green_space_equity_score > 120 & accessibility_score > 70 ~ "Well-Served",
      green_space_equity_score > 100 & accessibility_score > 50 ~ "Adequate",
      green_space_equity_score > 80 & accessibility_score > 30 ~ "Moderate Deficit",
      TRUE ~ "Significant Deficit"
    )
  ) %>%
  arrange(desc(green_space_equity_score))

# Save equity analysis
write_csv(equity_analysis, 
         file.path(dir_analysis, "03_green_space_equity_analysis.csv"))

cat("✓ Equity analysis complete\n")
cat("\nEquity categories:\n")
print(table(equity_analysis$equity_category))
cat("\n")

# ============================================================================
# PART 3: Spatial Green Space Analysis
# ============================================================================
cat("--- Spatial Green Space Patterns ---\n")

# Create density map of green spaces
green_wgs <- st_transform(green_hk, wgs84)

# Calculate green space density by district
green_density_by_district <- hk_master %>%
  st_drop_geometry() %>%
  select(name, n_green_spaces) %>%
  mutate(
    area_km2 = st_area(hk_master) / 1e6 %>% as.numeric(),
    green_density = n_green_spaces / area_km2,
    green_density_score = standardize_to_100(green_density)
  )

cat("✓ Spatial patterns analyzed\n\n")

# ============================================================================
# PART 4: Green Space Type Classification
# ============================================================================
cat("--- Green Space Type Analysis ---\n")

green_type_analysis <- green_spaces_osm %>%
  st_drop_geometry() %>%
  group_by(fclass) %>%
  summarise(
    count = n(),
    pct_total = n() / nrow(green_spaces_osm) * 100,
    .groups = "drop"
  ) %>%
  arrange(desc(count))

# Map green space types to categories
green_type_categories <- green_type_analysis %>%
  mutate(
    category = case_when(
      fclass %in% c("park", "garden", "recreation_ground") ~ "Recreation",
      fclass %in% c("forest", "nature_reserve", "meadow") ~ "Natural",
      fclass %in% c("playground", "sports_centre", "pitch") ~ "Active",
      fclass == "dog_park" ~ "Pet-Specific",
      TRUE ~ "Other"
    )
  )

write_csv(green_type_analysis, 
         file.path(dir_analysis, "03_green_space_types.csv"))

cat("✓ Green space types classified\n")
print(green_type_categories)
cat("\n")

# ============================================================================
# PART 5: Visualization - Green Space Metrics Map
# ============================================================================
cat("--- Creating Green Space Visualizations ---\n")

hk_wgs <- st_transform(hk_master, wgs84) %>% st_make_valid()

# Merge equity metrics with spatial data
hk_with_equity <- hk_wgs %>%
  left_join(equity_analysis %>% select(-total_pop, -pop_density, -aging_ratio, -n_dog_parks),
           by = c("name" = "name"))

# Map 1: Green space per capita
map_equity_1 <- ggplot(hk_with_equity) +
  geom_sf(aes(fill = green_space_equity_score), color = "grey40", size = 0.3) +
  scale_fill_viridis_c(option = "D", name = "Equity Score") +
  geom_sf_text(aes(label = substr(name, 1, 3)), size = 2.5, color = "white", fontface = "bold") +
  labs(title = "Green Space Equity Score") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 12, hjust = 0.5))

# Map 2: Accessibility score
map_equity_2 <- ggplot(hk_with_equity) +
  geom_sf(aes(fill = accessibility_score), color = "grey40", size = 0.3) +
  scale_fill_viridis_c(option = "C", name = "Accessibility") +
  geom_sf_text(aes(label = substr(name, 1, 3)), size = 2.5, color = "white", fontface = "bold") +
  labs(title = "Green Space Accessibility Score") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 12, hjust = 0.5))

# Map 3: Green coverage percentage
map_equity_3 <- ggplot(hk_with_equity) +
  geom_sf(aes(fill = green_coverage_pct), color = "grey40", size = 0.3) +
  scale_fill_viridis_c(option = "G", name = "Coverage %") +
  geom_sf_text(aes(label = substr(name, 1, 3)), size = 2.5, color = "white", fontface = "bold") +
  labs(title = "Green Space Coverage (%)") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 12, hjust = 0.5))

# Combine maps
p_green_maps <- (map_equity_1 | map_equity_2 | map_equity_3) +
  plot_annotation(
    title = "Hong Kong Green Space Equity & Accessibility Indicators",
    theme = theme(plot.title = element_text(face = "bold", size = 14, hjust = 0.5))
  )

ggsave(
  file.path(dir_figures, "03_green_space_equity_maps.png"),
  p_green_maps,
  width = 16, height = 6, dpi = 300
)

cat("✓ Green space equity maps created\n\n")

# ============================================================================
# PART 6: Bar Plot - Equity Categories
# ============================================================================
cat("--- Creating Category Distribution Plot ---\n")

equity_summary <- equity_analysis %>%
  group_by(equity_category) %>%
  summarise(
    n_districts = n(),
    avg_equity_score = mean(green_space_equity_score),
    avg_accessibility = mean(accessibility_score),
    total_population = sum(total_pop),
    .groups = "drop"
  ) %>%
  mutate(equity_category = factor(equity_category,
                                  levels = c("Well-Served", "Adequate",
                                           "Moderate Deficit", "Significant Deficit")))

p_equity_bar <- equity_summary %>%
  ggplot(aes(x = equity_category, y = n_districts, fill = equity_category)) +
  geom_col(color = "white", size = 1) +
  scale_fill_manual(
    values = c("Well-Served" = "#06A77D",
              "Adequate" = "#90EE90",
              "Moderate Deficit" = "#FFD700",
              "Significant Deficit" = "#FF6B6B"),
    guide = "none"
  ) +
  geom_text(aes(label = n_districts), vjust = -0.5, fontface = "bold") +
  labs(
    title = "District Distribution by Green Space Equity Category",
    x = "Equity Category",
    y = "Number of Districts"
  ) +
  theme_hk +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(
  file.path(dir_figures, "03_equity_category_distribution.png"),
  p_equity_bar,
  width = 10, height = 6, dpi = 300
)

cat("✓ Equity category plot created\n\n")

# ============================================================================
# PART 7: Green Space Type Pie Chart
# ============================================================================
cat("--- Creating Green Space Type Distribution ---\n")

p_type_pie <- green_type_categories %>%
  group_by(category) %>%
  summarise(count = sum(count), pct = sum(pct_total), .groups = "drop") %>%
  ggplot(aes(x = "", y = count, fill = category)) +
  geom_col(color = "white", size = 2) +
  coord_polar(theta = "y") +
  scale_fill_brewer(palette = "Set2", name = "Green Space Type") +
  geom_label(aes(label = sprintf("%d\n(%.1f%%)", count, pct)),
            position = position_stack(vjust = 0.5),
            fontface = "bold", size = 3) +
  labs(title = "Hong Kong Green Space Type Distribution") +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 14, hjust = 0.5),
    legend.position = "right"
  )

ggsave(
  file.path(dir_figures, "03_green_space_type_pie.png"),
  p_type_pie,
  width = 10, height = 7, dpi = 300
)

cat("✓ Green space type pie chart created\n\n")

# ============================================================================
# PART 8: Save Results
# ============================================================================
cat("--- Saving Analysis Results ---\n")

save(
  accessibility_results, equity_analysis, green_density_by_district,
  green_type_categories,
  file = file.path(dir_analysis, "03_green_space_results.RData")
)

# ============================================================================
# Summary Report
# ============================================================================
cat("\n===============================================\n")
cat("Green Space Analysis Complete!\n")
cat("===============================================\n\n")

summary_text <- sprintf(
"GREEN SPACE ANALYSIS SUMMARY

Total Green Spaces Identified: %d

GREEN SPACE EQUITY:
- Well-Served Districts: %d
- Adequate Districts: %d
- Moderate Deficit Districts: %d
- Significant Deficit Districts: %d

ACCESSIBILITY:
- Mean distance to nearest green space: %.0f meters
- Districts with green space within 500m: %d
- Districts with green space within 1km: %d

GREEN SPACE TYPES:
%s

KEY FINDINGS:
- Average green area per capita: %.1f m²/person
- Average green coverage: %.1f%% of total area
- Green space concentration: %s

RECOMMENDATIONS:
- Priority intervention areas: %s
- High-equity districts for benchmarking: %s

",

nrow(green_spaces_osm),
sum(equity_analysis$equity_category == "Well-Served"),
sum(equity_analysis$equity_category == "Adequate"),
sum(equity_analysis$equity_category == "Moderate Deficit"),
sum(equity_analysis$equity_category == "Significant Deficit"),

mean(accessibility_results$dist_nearest_green_m, na.rm = TRUE),
sum(accessibility_results$n_green_within_500m > 0),
sum(accessibility_results$n_green_within_1km > 0),

paste(capture.output(print(green_type_categories)), collapse = "\n"),

mean(hk_master$green_area_per_capita, na.rm = TRUE),
mean(hk_master$green_space_pct, na.rm = TRUE),
ifelse(max(equity_analysis$green_space_equity_score) > 150, "High", "Moderate"),

paste(head(equity_analysis$name[equity_analysis$equity_category == "Significant Deficit"], 3), collapse = ", "),
paste(head(equity_analysis$name[equity_analysis$equity_category == "Well-Served"], 3), collapse = ", ")
)

write(summary_text, file.path(dir_analysis, "03_green_space_summary.txt"))
cat(summary_text)

cat("Output files:\n")
cat("  ✓ green_space_equity_analysis.csv\n")
cat("  ✓ green_space_types.csv\n")
cat("  ✓ Multiple visualization outputs\n")
cat("  ✓ Analysis summary report\n\n")
cat("Next step: Run 04_population_health_analysis.R\n")
cat("===============================================\n\n")
