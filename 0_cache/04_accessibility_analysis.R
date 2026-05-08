# ============================================================================
# 04_accessibility_analysis.R
# Green Space & Healthcare Accessibility Analysis
# ============================================================================
# Techniques:
#   1. Buffer analysis (400m, 800m, 1600m walkable zones)
#   2. Kernel Density Estimation (KDE) of pet gardens
#   3. Voronoi / Thiessen polygons for service areas
#   4. Spatial interpolation (IDW) of green space accessibility
#   5. Two-Step Floating Catchment Area (2SFCA) for hospitals
# ============================================================================

source("00_setup.R")
load(file.path(dir_output, "prepared_data.RData"))

# ============================================================================
# 1. Buffer Analysis - Green Space Walkable Zones
# ============================================================================
cat("\n=== Buffer Analysis: Green Space Walkable Zones ===\n")

# Buffer distances (meters) - typical walking distances
buffer_distances <- c(400, 800, 1600)  # ~5min, ~10min, ~20min walk

# Use park centroids for point-based buffers
park_pts <- st_centroid(parks_hk)

buffer_results <- list()
for (d in buffer_distances) {
  cat(sprintf("Creating %dm buffer...\n", d))
  buf <- st_buffer(park_pts, dist = d)
  buf_union <- st_union(buf)
  buffer_results[[as.character(d)]] <- buf_union
}

# Calculate coverage per district for each buffer distance
cat("\n--- Green Space Buffer Coverage by District ---\n")

for (d in buffer_distances) {
  buf_union <- buffer_results[[as.character(d)]]
  
  # Intersection with each district
  coverage <- sapply(1:nrow(districts_hk), function(i) {
    isect <- st_intersection(buf_union, st_geometry(districts_hk[i, ]))
    if (length(isect) == 0) return(0)
    as.numeric(st_area(isect))
  })
  
  col_name <- paste0("green_buf_", d, "m_pct")
  master[[col_name]] <- (coverage / as.numeric(st_area(districts_hk))) * 100
}

cat("Buffer coverage columns added to master.\n")

# Visualize buffer zones
master_wgs <- st_transform(master, wgs84)

# Buffer map - convert sfc objects to sf for ggplot
buf_sf_1600 <- st_sf(geometry = st_sfc(buffer_results[["1600"]], crs = hk_crs))
buf_sf_800  <- st_sf(geometry = st_sfc(buffer_results[["800"]],  crs = hk_crs))
buf_sf_400  <- st_sf(geometry = st_sfc(buffer_results[["400"]],  crs = hk_crs))

p_buf <- ggplot() +
  geom_sf(data = master_wgs, fill = "grey95", color = "grey60") +
  geom_sf(data = st_transform(buf_sf_1600, wgs84),
          fill = "#a1d99b", alpha = 0.3) +
  geom_sf(data = st_transform(buf_sf_800, wgs84),
          fill = "#41ab5d", alpha = 0.4) +
  geom_sf(data = st_transform(buf_sf_400, wgs84),
          fill = "#006d2c", alpha = 0.5) +
  geom_sf(data = master_wgs, fill = NA, color = "grey40", size = 0.5) +
  labs(title = "Green Space Walkable Zones",
       subtitle = "Dark green: 400m (5min) | Medium: 800m (10min) | Light: 1600m (20min)") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "map_green_buffers.png"), p_buf,
       width = 12, height = 8, dpi = 300)

# Bar chart of coverage by district
buf_coverage <- master %>%
  st_drop_geometry() %>%
  select(name, green_buf_400m_pct, green_buf_800m_pct, green_buf_1600m_pct) %>%
  pivot_longer(-name, names_to = "buffer", values_to = "coverage") %>%
  mutate(buffer = case_when(
    buffer == "green_buf_400m_pct" ~ "400m (5-min walk)",
    buffer == "green_buf_800m_pct" ~ "800m (10-min walk)",
    buffer == "green_buf_1600m_pct" ~ "1600m (20-min walk)"
  ))

p_buf_bar <- ggplot(buf_coverage,
                     aes(x = reorder(name, coverage), y = coverage, fill = buffer)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("#006d2c", "#41ab5d", "#a1d99b"),
                    name = "Buffer Distance") +
  coord_flip() +
  labs(title = "Green Space Buffer Coverage by District",
       subtitle = "% of district area within walking distance of green space",
       x = NULL, y = "Coverage (%)") +
  theme_hk

ggsave(file.path(dir_figures, "bar_buffer_coverage.png"), p_buf_bar,
       width = 12, height = 8, dpi = 300)

# ============================================================================
# 2. Kernel Density Estimation (KDE) - Pet Gardens
# ============================================================================
cat("\n=== KDE: Pet Garden Density ===\n")

# Convert pet gardens to ppp for spatstat
# Create observation window from simplified HK boundary
hk_union <- st_union(districts_hk) %>% st_make_valid()
# Simplify geometry to avoid conversion issues, then use bounding box as fallback
hk_owin <- tryCatch({
  hk_simple <- st_simplify(hk_union, dTolerance = 100)
  hk_simple <- st_make_valid(hk_simple)
  as.owin(as(hk_simple, "Spatial"))
}, error = function(e) {
  cat("  Using bounding box as observation window (geometry too complex)\n")
  bb <- st_bbox(hk_union)
  owin(xrange = c(bb["xmin"], bb["xmax"]),
       yrange = c(bb["ymin"], bb["ymax"]))
})

# Pet garden coordinates
pet_coords <- st_coordinates(pet_hk)
pet_ppp <- ppp(pet_coords[, 1], pet_coords[, 2], window = hk_owin)

cat("Pet garden point pattern:", npoints(pet_ppp), "points\n")

# KDE with different bandwidths
bw_default <- bw.diggle(pet_ppp)
cat("Diggle bandwidth:", bw_default, "m\n")

kde_pet <- density(pet_ppp, sigma = 2000)  # 2km bandwidth

# Plot KDE
png(file.path(dir_figures, "kde_pet_gardens.png"),
    width = 10, height = 8, units = "in", res = 300)
plot(kde_pet, main = "Kernel Density of Pet Gardens in Hong Kong",
     col = viridis(256))
plot(st_geometry(districts_hk), add = TRUE, border = "white", lwd = 1)
points(pet_coords, pch = 16, cex = 0.8, col = "red")
dev.off()

# Also compute KDE for all green spaces
green_pts_coords <- st_coordinates(st_centroid(parks_hk))
green_ppp <- ppp(green_pts_coords[, 1], green_pts_coords[, 2], window = hk_owin)

kde_green <- density(green_ppp, sigma = 1500)

png(file.path(dir_figures, "kde_green_spaces.png"),
    width = 10, height = 8, units = "in", res = 300)
plot(kde_green, main = "Kernel Density of Green Spaces in Hong Kong",
     col = hcl.colors(256, "Greens 3", rev = TRUE))
plot(st_geometry(districts_hk), add = TRUE, border = "grey30", lwd = 1)
dev.off()

# ============================================================================
# 3. Voronoi Polygons - Hospital Service Areas
# ============================================================================
cat("\n=== Voronoi: Hospital Service Areas ===\n")

hosp_pts <- st_geometry(hospitals_hk)

# Create Voronoi within HK boundary
hk_union_valid <- st_make_valid(hk_union)
voronoi <- st_voronoi(st_combine(hosp_pts), envelope = hk_union_valid)
voronoi_sf <- st_collection_extract(voronoi, "POLYGON")
voronoi_sf <- st_sf(geometry = voronoi_sf, crs = hk_crs)

# Clip to HK boundary
voronoi_clipped <- st_intersection(voronoi_sf, hk_union_valid)
# Ensure it's a proper sf object
if (!inherits(voronoi_clipped, "sf")) {
  voronoi_clipped <- st_sf(geometry = st_sfc(voronoi_clipped, crs = hk_crs))
}
voronoi_clipped$hospital_id <- 1:nrow(voronoi_clipped)

# Calculate area of each service zone
voronoi_clipped$service_area_km2 <- as.numeric(st_area(voronoi_clipped)) / 1e6

# Map Voronoi
png(file.path(dir_figures, "voronoi_hospitals.png"),
    width = 10, height = 8, units = "in", res = 300)
plot(st_geometry(voronoi_clipped), col = sample(viridis(nrow(voronoi_clipped))),
     border = "grey70",
     main = "Hospital Service Areas (Voronoi/Thiessen Polygons)")
plot(st_geometry(districts_hk), add = TRUE, border = "black", lwd = 1.5)
plot(st_geometry(hospitals_hk), add = TRUE, pch = 3, col = "red", cex = 1.2)
legend("bottomleft", legend = c("Hospital", "District boundary"),
       pch = c(3, NA), lty = c(NA, 1), col = c("red", "black"),
       lwd = c(NA, 1.5), bg = "white")
dev.off()

# ============================================================================
# 4. Spatial Interpolation (IDW) - Green Space Accessibility
# ============================================================================
cat("\n=== IDW Interpolation: Green Space Accessibility ===\n")

# Use district centroids with green_area_per_capita as known values
centroids_hk <- st_centroid(master)

# Create prediction grid
bbox <- st_bbox(districts_hk)
grid <- st_make_grid(districts_hk,
                      cellsize = c(500, 500),  # 500m grid
                      what = "centers")
grid_sf <- st_sf(geometry = grid)

# Keep only grid points inside HK
grid_in <- grid_sf[st_intersects(grid_sf, hk_union, sparse = FALSE)[, 1], ]

# IDW function
idw_predict <- function(known_pts, known_vals, pred_pts, power = 2) {
  known_coords <- st_coordinates(known_pts)
  pred_coords <- st_coordinates(pred_pts)
  
  predictions <- sapply(1:nrow(pred_coords), function(i) {
    d <- sqrt((pred_coords[i, 1] - known_coords[, 1])^2 +
              (pred_coords[i, 2] - known_coords[, 2])^2)
    d[d == 0] <- 1  # avoid division by zero
    w <- 1 / d^power
    sum(w * known_vals) / sum(w)
  })
  return(predictions)
}

# Run IDW for green space per capita
grid_in$green_idw <- idw_predict(
  centroids_hk,
  master$green_area_per_capita,
  grid_in,
  power = 2
)

# Convert to raster for plotting via terra
grid_in_wgs <- st_transform(grid_in, wgs84)

p_idw <- ggplot() +
  geom_sf(data = grid_in_wgs, aes(color = green_idw), size = 0.5) +
  scale_color_viridis_c(option = "G", direction = -1,
                         name = "Green Space\nPer Capita (m²)") +
  geom_sf(data = st_transform(districts_hk, wgs84),
          fill = NA, color = "grey30", size = 0.5) +
  labs(title = "IDW Interpolation: Green Space Accessibility",
       subtitle = "Inverse Distance Weighting (power=2) from district centroids") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "idw_green_accessibility.png"), p_idw,
       width = 12, height = 8, dpi = 300)

# IDW for aging ratio
grid_in$aging_idw <- idw_predict(centroids_hk, master$aging_ratio, grid_in)

p_idw_aging <- ggplot() +
  geom_sf(data = st_transform(grid_in, wgs84),
          aes(color = aging_idw), size = 0.5) +
  scale_color_viridis_c(option = "D", name = "Aging Ratio") +
  geom_sf(data = st_transform(districts_hk, wgs84),
          fill = NA, color = "grey30") +
  labs(title = "IDW Interpolation: Aging Ratio Surface") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "idw_aging_ratio.png"), p_idw_aging,
       width = 12, height = 8, dpi = 300)

# ============================================================================
# 5. Two-Step Floating Catchment Area (2SFCA) - Healthcare Access
# ============================================================================
cat("\n=== 2SFCA: Healthcare Accessibility Index ===\n")

# Step 1: For each hospital, calculate supply-to-demand ratio
# within catchment distance (e.g., 5km)
catchment_dist <- 5000  # 5km

# Population at district centroids
pop_pts <- centroids_hk
pop_pts$pop <- master$total_pop

# Distance matrix between hospitals and population centroids
dist_mat <- st_distance(hospitals_hk, pop_pts)  # hospitals x districts

# Assume each hospital has capacity = 1 (equal weight)
# For A&E hospitals, weight = 2
hosp_weight <- ifelse(hospitals_hk$has_AE == "Yes", 2, 1)

# Step 1: R_j = S_j / sum(P_k within d0)
R_j <- sapply(1:nrow(hospitals_hk), function(j) {
  within <- which(as.numeric(dist_mat[j, ]) <= catchment_dist)
  if (length(within) == 0) return(0)
  pop_sum <- sum(pop_pts$pop[within], na.rm = TRUE)
  if (pop_sum == 0) return(0)
  hosp_weight[j] / pop_sum
})

# Step 2: A_i = sum(R_j within d0 of i)
A_i <- sapply(1:nrow(pop_pts), function(i) {
  within <- which(as.numeric(dist_mat[, i]) <= catchment_dist)
  if (length(within) == 0) return(0)
  sum(R_j[within])
})

master$healthcare_access_2sfca <- A_i * 100000  # per 100,000

cat("2SFCA Healthcare Accessibility Index:\n")
print(master %>% st_drop_geometry() %>%
        select(name, healthcare_access_2sfca) %>%
        arrange(healthcare_access_2sfca))

# Map 2SFCA
master_wgs <- st_transform(master, wgs84)

p_2sfca <- ggplot(master_wgs) +
  geom_sf(aes(fill = healthcare_access_2sfca), color = "white", size = 0.5) +
  scale_fill_viridis_c(option = "C", name = "2SFCA Index\n(per 100k)") +
  geom_sf_text(aes(label = name), size = 2.5) +
  labs(title = "Healthcare Accessibility Index (2SFCA Method)",
       subtitle = "Accounts for hospital capacity and population demand within 5km") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "map_2sfca_healthcare.png"), p_2sfca,
       width = 12, height = 8, dpi = 300)

# ============================================================================
# 6. Save Results
# ============================================================================

save(master, buffer_results, kde_pet, kde_green, voronoi_clipped,
     grid_in,
     file = file.path(dir_output, "accessibility_results.RData"))

cat("\n=== Accessibility Analysis Complete! ===\n")
