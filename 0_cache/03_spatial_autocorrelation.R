# ============================================================================
# 03_spatial_autocorrelation.R
# Spatial Autocorrelation Analysis
# ============================================================================
# Techniques used:
#   1. Spatial Weights Matrix (Queen contiguity)
#   2. Global Moran's I - green space, population density, aging
#   3. Local Moran's I (LISA) - cluster/outlier detection
#   4. Getis-Ord Gi* - hotspot analysis
#   5. Join Count Statistic
# ============================================================================

source("00_setup.R")
load(file.path(dir_output, "prepared_data.RData"))

# ============================================================================
# 1. Spatial Weights Matrix
# ============================================================================
cat("\n=== Constructing Spatial Weights Matrix ===\n")

# Queen contiguity (shares edge or vertex)
nb_queen <- poly2nb(master, queen = TRUE)
summary(nb_queen)

# Check for islands (districts with no neighbors)
no_nb <- which(card(nb_queen) == 0)
if (length(no_nb) > 0) {
  cat("WARNING: Districts with no neighbors:", master$name[no_nb], "\n")
  cat("Adding k-nearest neighbor links for these islands...\n")
  # Use k=1 nearest neighbor for islands
  coords <- st_coordinates(st_centroid(master))
  knn1 <- knearneigh(coords, k = 1)
  nb_knn <- knn2nb(knn1)
  # Union the two neighbor lists
  nb_queen <- union.nb(nb_queen, nb_knn)
}

# Row-standardized weights
lw_queen <- nb2listw(nb_queen, style = "W", zero.policy = TRUE)

cat("Spatial weights matrix created (Queen contiguity, row-standardized)\n")

# Visualize neighbor links
png(file.path(dir_figures, "spatial_weights_queen.png"),
    width = 10, height = 8, units = "in", res = 300)
plot(st_geometry(master), border = "grey60", main = "Queen Contiguity Weights")
plot(nb_queen, st_coordinates(st_centroid(master)),
     add = TRUE, col = "red", lwd = 1.5)
text(st_coordinates(st_centroid(master)), labels = master$name,
     cex = 0.6, pos = 3)
dev.off()

# ============================================================================
# 2. Global Moran's I
# ============================================================================
cat("\n=== Global Moran's I Tests ===\n")

# Function to run and display Moran's I
run_moran <- function(x, listw, var_name) {
  mt <- moran.test(x, listw, zero.policy = TRUE)
  mc <- moran.mc(x, listw, nsim = 999, zero.policy = TRUE)
  cat(sprintf("\n--- %s ---\n", var_name))
  cat(sprintf("  Moran's I = %.4f\n", mt$estimate[1]))
  cat(sprintf("  Expected  = %.4f\n", mt$estimate[2]))
  cat(sprintf("  Variance  = %.6f\n", mt$estimate[3]))
  cat(sprintf("  Z-score   = %.4f\n", mt$statistic))
  cat(sprintf("  p-value   = %.4f (analytical)\n", mt$p.value))
  cat(sprintf("  p-value   = %.4f (Monte Carlo, 999 sims)\n", mc$p.value))
  if (mt$p.value < 0.05) {
    cat("  => SIGNIFICANT spatial autocorrelation detected!\n")
  } else {
    cat("  => No significant spatial autocorrelation.\n")
  }
  return(list(test = mt, mc = mc))
}

# Test key variables
moran_green <- run_moran(master$green_area_per_capita, lw_queen,
                          "Green Space Per Capita")
moran_pop   <- run_moran(master$pop_density, lw_queen,
                          "Population Density")
moran_aging <- run_moran(master$aging_ratio, lw_queen,
                          "Aging Ratio")
moran_hosp  <- run_moran(master$hospitals_per_100k, lw_queen,
                          "Hospitals per 100k")

# Moran scatter plot (Green space per capita)
png(file.path(dir_figures, "moran_scatter_green.png"),
    width = 8, height = 7, units = "in", res = 300)
moran.plot(master$green_area_per_capita, lw_queen,
           labels = master$name,
           main = "Moran Scatter Plot: Green Space Per Capita",
           xlab = "Green Space Per Capita (m²)",
           ylab = "Spatially Lagged Green Space",
           zero.policy = TRUE)
dev.off()

# Moran scatter plot (Population Density)
png(file.path(dir_figures, "moran_scatter_pop_density.png"),
    width = 8, height = 7, units = "in", res = 300)
moran.plot(master$pop_density, lw_queen,
           labels = master$name,
           main = "Moran Scatter Plot: Population Density",
           xlab = "Population Density (per km²)",
           ylab = "Spatially Lagged Pop Density",
           zero.policy = TRUE)
dev.off()

# ============================================================================
# 3. Local Moran's I (LISA)
# ============================================================================
cat("\n=== Local Moran's I (LISA) ===\n")

# LISA for green space per capita
lisa_green <- localmoran(master$green_area_per_capita, lw_queen,
                          zero.policy = TRUE)

# Add LISA results to master
master$lisa_green_Ii <- lisa_green[, 1]   # Local Moran's I
master$lisa_green_z  <- lisa_green[, 4]   # Z-score
master$lisa_green_p  <- lisa_green[, 5]   # p-value

# Classify LISA clusters
# Quadrant: based on value and lag
x_scaled <- scale(master$green_area_per_capita)[, 1]
lag_scaled <- lag.listw(lw_queen, x_scaled, zero.policy = TRUE)

master$lisa_green_cluster <- case_when(
  master$lisa_green_p > 0.05 ~ "Not Significant",
  x_scaled > 0 & lag_scaled > 0 ~ "High-High",
  x_scaled < 0 & lag_scaled < 0 ~ "Low-Low",
  x_scaled > 0 & lag_scaled < 0 ~ "High-Low",
  x_scaled < 0 & lag_scaled > 0 ~ "Low-High",
  TRUE ~ "Not Significant"
)

cat("LISA cluster counts (Green Space):\n")
print(table(master$lisa_green_cluster))

# LISA Map
lisa_colors <- c("High-High" = "#FF0000", "Low-Low" = "#0000FF",
                  "High-Low" = "#FFA500", "Low-High" = "#ADD8E6",
                  "Not Significant" = "#E8E8E8")

master_wgs <- st_transform(master, wgs84)

p_lisa_green <- ggplot(master_wgs) +
  geom_sf(aes(fill = lisa_green_cluster), color = "white", size = 0.5) +
  scale_fill_manual(values = lisa_colors, name = "LISA Cluster") +
  geom_sf_text(aes(label = name), size = 2.5) +
  labs(title = "LISA Cluster Map: Green Space Per Capita",
       subtitle = "Local Moran's I (p < 0.05)") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14),
        legend.position = "right")

ggsave(file.path(dir_figures, "lisa_green_space.png"), p_lisa_green,
       width = 12, height = 8, dpi = 300)

# LISA for population density
lisa_pop <- localmoran(master$pop_density, lw_queen, zero.policy = TRUE)
master$lisa_pop_Ii <- lisa_pop[, 1]
master$lisa_pop_p  <- lisa_pop[, 5]

x_pop <- scale(master$pop_density)[, 1]
lag_pop <- lag.listw(lw_queen, x_pop, zero.policy = TRUE)

master$lisa_pop_cluster <- case_when(
  master$lisa_pop_p > 0.05 ~ "Not Significant",
  x_pop > 0 & lag_pop > 0 ~ "High-High",
  x_pop < 0 & lag_pop < 0 ~ "Low-Low",
  x_pop > 0 & lag_pop < 0 ~ "High-Low",
  x_pop < 0 & lag_pop > 0 ~ "Low-High",
  TRUE ~ "Not Significant"
)

master_wgs <- st_transform(master, wgs84)

p_lisa_pop <- ggplot(master_wgs) +
  geom_sf(aes(fill = lisa_pop_cluster), color = "white", size = 0.5) +
  scale_fill_manual(values = lisa_colors, name = "LISA Cluster") +
  geom_sf_text(aes(label = name), size = 2.5) +
  labs(title = "LISA Cluster Map: Population Density",
       subtitle = "Local Moran's I (p < 0.05)") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "lisa_pop_density.png"), p_lisa_pop,
       width = 12, height = 8, dpi = 300)

# ============================================================================
# 4. Getis-Ord Gi* (Hotspot Analysis)
# ============================================================================
cat("\n=== Getis-Ord Gi* Hotspot Analysis ===\n")

# Need binary weights for Gi*
lw_binary <- nb2listw(nb_queen, style = "B", zero.policy = TRUE)

# Include self-neighbors for Gi*
nb_self <- include.self(nb_queen)
lw_self <- nb2listw(nb_self, style = "B", zero.policy = TRUE)

# Gi* for green space
gi_green <- localG(master$green_area_per_capita, lw_self)
master$gi_green <- as.numeric(gi_green)

master$gi_green_class <- case_when(
  master$gi_green > 2.58  ~ "Hot Spot (99% CI)",
  master$gi_green > 1.96  ~ "Hot Spot (95% CI)",
  master$gi_green > 1.65  ~ "Hot Spot (90% CI)",
  master$gi_green < -2.58 ~ "Cold Spot (99% CI)",
  master$gi_green < -1.96 ~ "Cold Spot (95% CI)",
  master$gi_green < -1.65 ~ "Cold Spot (90% CI)",
  TRUE ~ "Not Significant"
)

cat("Gi* hotspot counts (Green Space):\n")
print(table(master$gi_green_class))

# Gi* for population density
gi_pop <- localG(master$pop_density, lw_self)
master$gi_pop <- as.numeric(gi_pop)

master$gi_pop_class <- case_when(
  master$gi_pop > 2.58  ~ "Hot Spot (99% CI)",
  master$gi_pop > 1.96  ~ "Hot Spot (95% CI)",
  master$gi_pop > 1.65  ~ "Hot Spot (90% CI)",
  master$gi_pop < -2.58 ~ "Cold Spot (99% CI)",
  master$gi_pop < -1.96 ~ "Cold Spot (95% CI)",
  master$gi_pop < -1.65 ~ "Cold Spot (90% CI)",
  TRUE ~ "Not Significant"
)

# Hotspot maps
hotspot_colors <- c(
  "Hot Spot (99% CI)" = "#d7191c",
  "Hot Spot (95% CI)" = "#fdae61",
  "Hot Spot (90% CI)" = "#fee08b",
  "Not Significant"   = "#f0f0f0",
  "Cold Spot (90% CI)" = "#d1e5f0",
  "Cold Spot (95% CI)" = "#74add1",
  "Cold Spot (99% CI)" = "#2c7bb6"
)

master_wgs <- st_transform(master, wgs84)

p_gi_green <- ggplot(master_wgs) +
  geom_sf(aes(fill = gi_green_class), color = "white", size = 0.5) +
  scale_fill_manual(values = hotspot_colors, name = "Gi* Classification",
                    drop = FALSE) +
  geom_sf_text(aes(label = name), size = 2.5) +
  labs(title = "Getis-Ord Gi* Hotspot Map: Green Space Per Capita",
       subtitle = "Clustering of high/low values") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "hotspot_green_space.png"), p_gi_green,
       width = 12, height = 8, dpi = 300)

p_gi_pop <- ggplot(master_wgs) +
  geom_sf(aes(fill = gi_pop_class), color = "white", size = 0.5) +
  scale_fill_manual(values = hotspot_colors, name = "Gi* Classification",
                    drop = FALSE) +
  geom_sf_text(aes(label = name), size = 2.5) +
  labs(title = "Getis-Ord Gi* Hotspot Map: Population Density") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "hotspot_pop_density.png"), p_gi_pop,
       width = 12, height = 8, dpi = 300)

# ============================================================================
# 5. Summary Output
# ============================================================================

# Save updated master with spatial stats
st_write(st_transform(master, wgs84),
         file.path(dir_output, "master_with_spatial_stats.geojson"),
         delete_dsn = TRUE)

save(master, lw_queen, nb_queen, lw_binary, lw_self,
     moran_green, moran_pop, moran_aging, moran_hosp,
     lisa_green, lisa_pop,
     file = file.path(dir_output, "spatial_autocorrelation_results.RData"))

cat("\n=== Spatial Autocorrelation Analysis Complete! ===\n")
