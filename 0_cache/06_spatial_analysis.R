# ============================================================================
# 06_spatial_analysis.R
# Spatial Statistics: Autocorrelation, Hot Spots & Clustering Analysis
# ============================================================================
# This script creates:
#   1. Spatial autocorrelation analysis (Moran's I, LISA)
#   2. Hot spot detection for dog parks and green space
#   3. Spatial clustering patterns
#   4. Spatial regression modeling
# ============================================================================

source("00_setup.R")
load(file.path(dir_analysis, "01_integrated_data.RData"))

cat("\n===============================================\n")
cat("Spatial Analysis Module\n")
cat("===============================================\n\n")

# ============================================================================
# PART 1: Create Spatial Weights Matrix
# ============================================================================
cat("--- Creating Spatial Weights Matrix ---\n")

# Project to HK1980 for accurate distance calculations
districts_hk <- st_transform(hk_master, hk_crs) %>% st_make_valid()

# Create contiguity-based weights (Queen's case - neighbors sharing edge or corner)
neighbors <- st_touches(districts_hk, sparse = FALSE)
weights_list <- st_touches(districts_hk, sparse = TRUE)
weights_matrix <- nb2mat(st_touches(districts_hk, sparse = TRUE), style = "W")

cat("✓ Spatial weights matrix created\n")
cat(sprintf("  Average number of neighbors: %.1f\n", 
            mean(rowSums(weights_matrix))))
cat("\n")

# ============================================================================
# PART 2: Global Moran's I - Spatial Autocorrelation Test
# ============================================================================
cat("--- Global Spatial Autocorrelation Analysis ---\n")

# Variables to test for spatial autocorrelation
variables_to_test <- c(
  "dog_parks_per_100k",
  "green_area_per_capita",
  "pop_density",
  "aging_ratio",
  "environmental_score",
  "livability_score"
)

autocorrelation_results <- data.frame()

for (var in variables_to_test) {
  # Extract variable values
  y <- districts_hk[[var]]
  
  # Calculate global Moran's I
  morans_i <- moran(y, weights_matrix, n = length(y), S0 = sum(weights_matrix))
  
  # Perform permutation test
  morans_test <- moran.test(y, mat2listw(weights_matrix), alternative = "two.sided")
  
  autocorrelation_results <- rbind(autocorrelation_results,
    data.frame(
      variable = var,
      morans_i = round(morans_i, 4),
      p_value = round(morans_test$p.value, 4),
      significant = morans_test$p.value < 0.05,
      interpretation = ifelse(morans_test$p.value < 0.05 & morans_i > 0,
                             "Positive Autocorrelation (Clustered)",
                             ifelse(morans_test$p.value < 0.05 & morans_i < 0,
                                   "Negative Autocorrelation (Dispersed)",
                                   "No Significant Autocorrelation"))
    )
  )
}

write_csv(autocorrelation_results,
         file.path(dir_analysis, "06_spatial_autocorrelation_results.csv"))

cat("✓ Global Moran's I analysis complete\n\n")
print(autocorrelation_results)
cat("\n")

# ============================================================================
# PART 3: Local Indicators of Spatial Association (LISA)
# ============================================================================
cat("--- Local Spatial Clustering Analysis (LISA) ---\n")

lisa_results <- list()

for (var in variables_to_test[1:3]) {  # Focus on key variables
  y <- districts_hk[[var]]
  
  # Calculate local Moran's I
  lisa_stats <- localmoran(y, mat2listw(weights_matrix), alternative = "two.sided")
  
  # Create LISA classification
  lisa_clusters <- data.frame(
    name = districts_hk$name,
    variable = var,
    local_i = lisa_stats[, "Ii"],
    p_value = lisa_stats[, "Pr(z > 0)"],
    significant = lisa_stats[, "Pr(z > 0)"] < 0.05,
    cluster_type = NA
  )
  
  # Classify clusters
  for (i in 1:nrow(lisa_clusters)) {
    if (!lisa_clusters$significant[i]) {
      lisa_clusters$cluster_type[i] <- "Not Significant"
    } else {
      y_centered <- y - mean(y, na.rm = TRUE)
      
      # Get average neighbor value (spatial lag)
      row_sums <- rowSums(weights_matrix)
      spatial_lag <- weights_matrix %*% y / row_sums
      lag_centered <- spatial_lag - mean(spatial_lag, na.rm = TRUE)
      
      if (y_centered[i] > 0 & lag_centered[i] > 0) {
        lisa_clusters$cluster_type[i] <- "High-High"
      } else if (y_centered[i] < 0 & lag_centered[i] < 0) {
        lisa_clusters$cluster_type[i] <- "Low-Low"
      } else if (y_centered[i] > 0 & lag_centered[i] < 0) {
        lisa_clusters$cluster_type[i] <- "High-Low (Outlier)"
      } else {
        lisa_clusters$cluster_type[i] <- "Low-High (Outlier)"
      }
    }
  }
  
  lisa_results[[var]] <- lisa_clusters
}

# Combine and save LISA results
lisa_combined <- bind_rows(lisa_results)
write_csv(lisa_combined,
         file.path(dir_analysis, "06_lisa_cluster_analysis.csv"))

cat("✓ LISA clustering analysis complete\n\n")

for (var in unique(lisa_combined$variable)) {
  cat(sprintf("%s:\n", var))
  cluster_dist <- table(lisa_combined$cluster_type[lisa_combined$variable == var])
  print(cluster_dist)
  cat("\n")
}

# ============================================================================
# PART 4: Hot Spot Analysis using Getis-Ord Gi*
# ============================================================================
cat("--- Hot Spot Detection (Getis-Ord Gi*) ---\n")

# Create distance-based weights (useful for point data, adapted for areas)
# Using inclusive weights (Queen's case)
weights_queen <- nb2listw(st_touches(districts_hk, sparse = TRUE), style = "B")

hotspot_results <- data.frame()

for (var in c("dog_parks_per_100k", "green_area_per_capita")) {
  y <- districts_hk[[var]]
  
  # Calculate Getis-Ord Gi* statistics
  gi_stats <- localG(y, weights_queen, alternative = "two.sided")
  
  # Create hot spot classification
  hotspot_dist <- data.frame(
    name = districts_hk$name,
    variable = var,
    gi_stat = as.numeric(gi_stats),
    p_value = 2 * pnorm(-abs(as.numeric(gi_stats))),  # Two-tailed p-value
    hotspot_type = NA
  )
  
  # Classify hot/cold spots
  hotspot_dist$hotspot_type <- case_when(
    hotspot_dist$p_value < 0.05 & hotspot_dist$gi_stat > 0 ~ "Hot Spot",
    hotspot_dist$p_value < 0.05 & hotspot_dist$gi_stat < 0 ~ "Cold Spot",
    hotspot_dist$p_value < 0.10 & hotspot_dist$gi_stat > 0 ~ "Warm Spot (p<0.1)",
    hotspot_dist$p_value < 0.10 & hotspot_dist$gi_stat < 0 ~ "Cool Spot (p<0.1)",
    TRUE ~ "Not Significant"
  )
  
  hotspot_results <- rbind(hotspot_results, hotspot_dist)
}

write_csv(hotspot_results,
         file.path(dir_analysis, "06_hotspot_analysis.csv"))

cat("✓ Hot spot analysis complete\n\n")

for (var in unique(hotspot_results$variable)) {
  cat(sprintf("%s:\n", var))
  hotspot_dist <- table(hotspot_results$hotspot_type[hotspot_results$variable == var])
  print(hotspot_dist)
  cat("\n")
}

# ============================================================================
# PART 5: Visualization - LISA Cluster Map
# ============================================================================
cat("--- Creating Spatial Analysis Visualizations ---\n")

hk_wgs <- st_transform(hk_master, wgs84) %>% st_make_valid()

# Prepare LISA data for visualization - focus on dog parks
lisa_dogs <- lisa_results[["dog_parks_per_100k"]] %>%
  mutate(
    cluster_type = factor(cluster_type,
                         levels = c("High-High", "Low-Low", "High-Low (Outlier)",
                                  "Low-High (Outlier)", "Not Significant"))
  )

hk_lisa <- hk_wgs %>%
  left_join(lisa_dogs %>% select(name, cluster_type),
           by = "name")

# Map: LISA clusters for dog parks
map_lisa <- ggplot(hk_lisa) +
  geom_sf(aes(fill = cluster_type), color = "grey40", size = 0.3) +
  scale_fill_manual(
    values = c(
      "High-High" = "#D62828",
      "Low-Low" = "#1B4965",
      "High-Low (Outlier)" = "#F77F00",
      "Low-High (Outlier)" = "#06A77D",
      "Not Significant" = "#E0E0E0"
    ),
    name = "Cluster Type",
    na.translate = FALSE
  ) +
  geom_sf_text(aes(label = substr(name, 1, 3)), size = 2.5, color = "white",
              fontface = "bold") +
  labs(
    title = "Dog Parks: Local Spatial Clustering (LISA)",
    subtitle = "High-High: concentrated supply | Low-Low: sparse supply"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 12, hjust = 0.5),
    plot.subtitle = element_text(size = 9, color = "grey40", hjust = 0.5),
    legend.position = "right"
  )

ggsave(
  file.path(dir_figures, "06_lisa_cluster_map_dog_parks.png"),
  map_lisa,
  width = 12, height = 9, dpi = 300
)

cat("✓ LISA cluster map created\n")

# ============================================================================
# PART 6: Visualization - Hot Spot Map
# ============================================================================
cat("--- Creating Hot Spot Visualization ---\n")

# Prepare hot spot data
hotspot_dogs <- hotspot_results %>%
  filter(variable == "dog_parks_per_100k") %>%
  mutate(
    hotspot_type = factor(hotspot_type,
                         levels = c("Hot Spot", "Warm Spot (p<0.1)",
                                   "Cool Spot (p<0.1)", "Cold Spot", "Not Significant"))
  )

hk_hotspot <- hk_wgs %>%
  left_join(hotspot_dogs %>% select(name, hotspot_type),
           by = "name")

# Map: Hot spots for dog parks
map_hotspot <- ggplot(hk_hotspot) +
  geom_sf(aes(fill = hotspot_type), color = "grey40", size = 0.3) +
  scale_fill_manual(
    values = c(
      "Hot Spot" = "#D62828",
      "Warm Spot (p<0.1)" = "#F77F00",
      "Cool Spot (p<0.1)" = "#90E0EF",
      "Cold Spot" = "#0077B6",
      "Not Significant" = "#E0E0E0"
    ),
    name = "Hot Spot Type",
    na.translate = FALSE
  ) +
  geom_sf_text(aes(label = substr(name, 1, 3)), size = 2.5, color = "white",
              fontface = "bold") +
  labs(
    title = "Dog Parks: Hot Spot Analysis (Getis-Ord Gi*)",
    subtitle = "Identifies clusters of high/low values at district level"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(face = "bold", size = 12, hjust = 0.5),
    plot.subtitle = element_text(size = 9, color = "grey40", hjust = 0.5),
    legend.position = "right"
  )

ggsave(
  file.path(dir_figures, "06_hotspot_map_dog_parks.png"),
  map_hotspot,
  width = 12, height = 9, dpi = 300
)

cat("✓ Hot spot map created\n\n")

# ============================================================================
# PART 7: Moran's I Scatter Plot
# ============================================================================
cat("--- Creating Moran's I Scatter Plots ---\n")

# For each variable, create Moran scatter plot
create_morans_plot <- function(data, var, weights_mat, plot_title) {
  y <- data[[var]]
  y_centered <- y - mean(y, na.rm = TRUE)
  
  # Calculate spatial lag
  row_sums <- rowSums(weights_mat)
  spatial_lag <- weights_mat %*% y / row_sums
  spatial_lag_centered <- spatial_lag - mean(spatial_lag, na.rm = TRUE)
  
  # Calculate Moran's I
  morans_i_val <- sum(y_centered * as.numeric(spatial_lag_centered)) / 
                  sum(y_centered^2) * (length(y_centered) / sum(weights_mat))
  
  plot_data <- data.frame(
    x = y_centered,
    y = as.numeric(spatial_lag_centered),
    district = data$name
  )
  
  p <- ggplot(plot_data, aes(x = x, y = y)) +
    geom_point(size = 3, alpha = 0.7, color = "#2E86AB") +
    geom_label_repel(aes(label = substr(district, 1, 3)), size = 2.5) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
    geom_smooth(method = "lm", se = FALSE, color = "red", size = 1) +
    labs(
      title = plot_title,
      subtitle = sprintf("Moran's I = %.3f", morans_i_val),
      x = "Standardized Variable",
      y = "Spatial Lag (Standardized)"
    ) +
    theme_hk +
    theme(plot.subtitle = element_text(size = 10, color = "grey40"))
  
  return(p)
}

# Create Moran scatter plots for key variables
p_morans_dogs <- create_morans_plot(
  st_drop_geometry(districts_hk), "dog_parks_per_100k", weights_matrix,
  "Moran's I Scatter Plot: Dog Parks"
)

p_morans_green <- create_morans_plot(
  st_drop_geometry(districts_hk), "green_area_per_capita", weights_matrix,
  "Moran's I Scatter Plot: Green Space"
)

p_morans_combined <- p_morans_dogs / p_morans_green

ggsave(
  file.path(dir_figures, "06_morans_i_scatterplots.png"),
  p_morans_combined,
  width = 12, height = 10, dpi = 300
)

cat("✓ Moran's I scatter plots created\n\n")

# ============================================================================
# PART 8: Save Results
# ============================================================================
cat("--- Saving Analysis Results ---\n")

save(
  autocorrelation_results, lisa_combined, hotspot_results,
  weights_matrix, weights_queen,
  file = file.path(dir_analysis, "06_spatial_analysis_results.RData")
)

# ============================================================================
# Summary Report
# ============================================================================
cat("\n===============================================\n")
cat("Spatial Analysis Complete!\n")
cat("===============================================\n\n")

summary_text <- sprintf(
"SPATIAL ANALYSIS SUMMARY

GLOBAL SPATIAL AUTOCORRELATION (Moran's I):

Dog Parks Per 100k:
  - Moran's I: %.4f
  - P-value: %.4f
  - Significant: %s
  - Interpretation: %s

Green Area Per Capita:
  - Moran's I: %.4f
  - P-value: %.4f
  - Significant: %s
  - Interpretation: %s

Population Density:
  - Moran's I: %.4f
  - P-value: %.4f
  - Significant: %s
  - Interpretation: %s

LOCAL SPATIAL CLUSTERS (LISA):

Dog Parks Hot Spots:
- High-High Clusters: %d districts
- Low-Low Clusters: %d districts
- High-Low Outliers: %d districts
- Low-High Outliers: %d districts

Green Space Hot Spots:
- High-High Clusters: %d districts
- Low-Low Clusters: %d districts
- High-Low Outliers: %d districts
- Low-High Outliers: %d districts

HOT SPOT DETECTION (Getis-Ord Gi*):

Dog Parks:
- Hot Spots (p<0.05): %d districts
- Warm Spots (p<0.10): %d districts
- Cool Spots (p<0.10): %d districts
- Cold Spots (p<0.05): %d districts

SPATIAL PATTERNS IDENTIFIED:
- Primary dog park cluster: %s
- Green space cold spot: %s
- Most isolated district (unique spatial profile): %s

KEY FINDINGS:
1. Dog parks show %s spatial pattern
2. Green space distribution exhibits %s clustering
3. Population density is %s autocorrelated

RECOMMENDATIONS FOR SPATIAL PLANNING:
- Target investment in identified cold spots: %s
- Learn from hot spot success factors: %s
- Address isolated/outlier districts: %s

",

autocorrelation_results$morans_i[1],
autocorrelation_results$p_value[1],
autocorrelation_results$significant[1],
autocorrelation_results$interpretation[1],

autocorrelation_results$morans_i[2],
autocorrelation_results$p_value[2],
autocorrelation_results$significant[2],
autocorrelation_results$interpretation[2],

autocorrelation_results$morans_i[3],
autocorrelation_results$p_value[3],
autocorrelation_results$significant[3],
autocorrelation_results$interpretation[3],

sum(lisa_combined$cluster_type[lisa_combined$variable == "dog_parks_per_100k"] == "High-High"),
sum(lisa_combined$cluster_type[lisa_combined$variable == "dog_parks_per_100k"] == "Low-Low"),
sum(lisa_combined$cluster_type[lisa_combined$variable == "dog_parks_per_100k"] == "High-Low (Outlier)"),
sum(lisa_combined$cluster_type[lisa_combined$variable == "dog_parks_per_100k"] == "Low-High (Outlier)"),

sum(lisa_combined$cluster_type[lisa_combined$variable == "green_area_per_capita"] == "High-High"),
sum(lisa_combined$cluster_type[lisa_combined$variable == "green_area_per_capita"] == "Low-Low"),
sum(lisa_combined$cluster_type[lisa_combined$variable == "green_area_per_capita"] == "High-Low (Outlier)"),
sum(lisa_combined$cluster_type[lisa_combined$variable == "green_area_per_capita"] == "Low-High (Outlier)"),

sum(hotspot_results$hotspot_type[hotspot_results$variable == "dog_parks_per_100k"] == "Hot Spot"),
sum(hotspot_results$hotspot_type[hotspot_results$variable == "dog_parks_per_100k"] == "Warm Spot (p<0.1)"),
sum(hotspot_results$hotspot_type[hotspot_results$variable == "dog_parks_per_100k"] == "Cool Spot (p<0.1)"),
sum(hotspot_results$hotspot_type[hotspot_results$variable == "dog_parks_per_100k"] == "Cold Spot"),

paste(head(lisa_combined$name[lisa_combined$variable == "dog_parks_per_100k" & 
                             lisa_combined$cluster_type == "High-High"], 2), collapse = ", "),
paste(head(lisa_combined$name[lisa_combined$variable == "green_area_per_capita" & 
                             lisa_combined$cluster_type == "Low-Low"], 2), collapse = ", "),
paste(head(lisa_combined$name[lisa_combined$cluster_type == "High-Low (Outlier)"], 2), collapse = ", "),

if(autocorrelation_results$interpretation[1] == "Positive Autocorrelation (Clustered)") 
  "significant clustered" else "dispersed",
if(autocorrelation_results$interpretation[2] == "Positive Autocorrelation (Clustered)") 
  "significant clustered" else "dispersed",
if(autocorrelation_results$interpretation[3] == "Positive Autocorrelation (Clustered)") 
  "strongly" else "weakly",

paste(head(hotspot_results$name[hotspot_results$variable == "dog_parks_per_100k" & 
                               hotspot_results$hotspot_type == "Cold Spot"], 2), collapse = ", "),
paste(head(hotspot_results$name[hotspot_results$variable == "dog_parks_per_100k" & 
                               hotspot_results$hotspot_type == "Hot Spot"], 2), collapse = ", "),
paste(head(lisa_combined$name[lisa_combined$cluster_type %in% c("High-Low (Outlier)", "Low-High (Outlier)")], 2), collapse = ", ")
)

write(summary_text, file.path(dir_analysis, "06_spatial_analysis_summary.txt"))
cat(summary_text)

cat("Output files:\n")
cat("  ✓ spatial_autocorrelation_results.csv\n")
cat("  ✓ lisa_cluster_analysis.csv\n")
cat("  ✓ hotspot_analysis.csv\n")
cat("  ✓ Multiple spatial visualization outputs\n")
cat("  ✓ Spatial analysis summary report\n\n")
cat("Next step: Run 07_interactive_dashboard.R\n")
cat("===============================================\n\n")
