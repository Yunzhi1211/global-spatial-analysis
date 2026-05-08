# ============================================================================
# 06_pet_garden_analysis.R
# Dedicated Pet Garden Spatial Analysis
# ============================================================================
# This script focuses specifically on pet gardens:
#   1. Nearest Neighbor Analysis (NNA) - clustering test
#   2. K-function / Ripley's K - multi-scale clustering
#   3. Pet garden accessibility by district
#   4. Relationship between pet gardens and demographics
#   5. Gap analysis - underserved areas
# ============================================================================

source("00_setup.R")
load(file.path(dir_output, "prepared_data.RData"))

# ============================================================================
# 1. Pet Garden Overview Map
# ============================================================================
cat("\n=== Pet Garden Analysis ===\n")
cat("Total pet gardens:", nrow(pet_gardens), "\n")

# Detailed map
pet_wgs <- st_transform(pet_gardens, wgs84)
master_wgs <- st_transform(master, wgs84)
districts_wgs <- st_transform(districts, wgs84)

p_pet_map <- ggplot() +
  geom_sf(data = master_wgs, aes(fill = pop_density), alpha = 0.5) +
  scale_fill_viridis_c(option = "B", name = "Pop Density\n(per km²)") +
  geom_sf(data = pet_wgs, color = "red", size = 3, shape = 17) +
  geom_sf_text(data = districts_wgs, aes(label = name),
               size = 2.5, color = "grey30") +
  labs(title = "Pet Gardens in Hong Kong",
       subtitle = paste(nrow(pet_gardens), "pet gardens across 18 districts"),
       caption = "Red triangles = pet garden locations") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "map_pet_gardens_overview.png"), p_pet_map,
       width = 12, height = 8, dpi = 300)

# ============================================================================
# 2. Nearest Neighbor Analysis
# ============================================================================
cat("\n--- Nearest Neighbor Analysis ---\n")

# Convert to ppp
hk_union <- st_union(districts_hk) %>% st_make_valid()
hk_owin <- tryCatch({
  hk_simple <- st_simplify(hk_union, dTolerance = 100)
  hk_simple <- st_make_valid(hk_simple)
  as.owin(as(hk_simple, "Spatial"))
}, error = function(e) {
  cat("  Using bounding box as observation window\n")
  bb <- st_bbox(hk_union)
  owin(xrange = c(bb["xmin"], bb["xmax"]),
       yrange = c(bb["ymin"], bb["ymax"]))
})

pet_coords <- st_coordinates(pet_hk)
pet_ppp <- ppp(pet_coords[, 1], pet_coords[, 2], window = hk_owin)

# Clark-Evans test for clustering
ce_test <- clarkevans.test(pet_ppp, correction = "none")
cat("\nClark-Evans Test:\n")
cat("  R statistic:", ce_test$statistic, "\n")
cat("  p-value:", ce_test$p.value, "\n")
cat("  Interpretation:", ifelse(ce_test$statistic < 1,
                                 "CLUSTERED (R < 1)",
                                 "DISPERSED (R > 1)"), "\n")

# Mean nearest neighbor distance
nnd <- nndist(pet_ppp)
cat("\nNearest Neighbor Distances:\n")
cat("  Mean:", mean(nnd), "m\n")
cat("  Median:", median(nnd), "m\n")
cat("  Min:", min(nnd), "m\n")
cat("  Max:", max(nnd), "m\n")

# ============================================================================
# 3. K-function (Ripley's K)
# ============================================================================
cat("\n--- Ripley's K-function ---\n")

# Compute K-function with envelope (Monte Carlo simulation)
K_pet <- envelope(pet_ppp, Kest, nsim = 99, verbose = FALSE)

png(file.path(dir_figures, "ripley_k_pet_gardens.png"),
    width = 8, height = 6, units = "in", res = 300)
plot(K_pet, main = "Ripley's K-function: Pet Gardens",
     xlab = "Distance (m)", ylab = "K(r)",
     legend = TRUE)
dev.off()

# L-function (normalized K)
L_pet <- envelope(pet_ppp, Lest, nsim = 99, verbose = FALSE)

png(file.path(dir_figures, "ripley_L_pet_gardens.png"),
    width = 8, height = 6, units = "in", res = 300)
plot(L_pet, main = "L-function: Pet Gardens (Normalized Ripley's K)",
     xlab = "Distance (m)", ylab = "L(r) - r",
     legend = TRUE)
abline(h = 0, lty = 2, col = "grey50")
dev.off()

# ============================================================================
# 4. Pet Garden Accessibility Analysis
# ============================================================================
cat("\n--- Pet Garden Accessibility by District ---\n")

# Count pet gardens per district
pet_per_district <- master %>%
  st_drop_geometry() %>%
  select(name, n_pet_gardens, total_pop, pop_density,
         pet_gardens_per_100k, dist_nearest_pet_km,
         aging_ratio, public_housing_pct)

cat("Districts with NO pet gardens:\n")
print(pet_per_district %>% filter(n_pet_gardens == 0) %>% pull(name))

cat("\nPet gardens per 100k population:\n")
print(pet_per_district %>%
        select(name, n_pet_gardens, pet_gardens_per_100k) %>%
        arrange(desc(pet_gardens_per_100k)))

# Buffer analysis for pet gardens
pet_buf_400  <- st_buffer(pet_hk, 400)   # 5-min walk
pet_buf_800  <- st_buffer(pet_hk, 800)   # 10-min walk
pet_buf_1600 <- st_buffer(pet_hk, 1600)  # 20-min walk

# Map pet garden service areas
p_pet_buf <- ggplot() +
  geom_sf(data = master_wgs, fill = "grey95", color = "grey60") +
  geom_sf(data = st_transform(st_union(pet_buf_1600), wgs84),
          fill = "#fdd0a2", alpha = 0.4) +
  geom_sf(data = st_transform(st_union(pet_buf_800), wgs84),
          fill = "#fdae6b", alpha = 0.5) +
  geom_sf(data = st_transform(st_union(pet_buf_400), wgs84),
          fill = "#e6550d", alpha = 0.6) +
  geom_sf(data = master_wgs, fill = NA, color = "grey40") +
  geom_sf(data = pet_wgs, color = "red", size = 2, shape = 17) +
  geom_sf_text(data = districts_wgs, aes(label = name), size = 2.3) +
  labs(title = "Pet Garden Service Areas",
       subtitle = "Dark: 400m (5min) | Medium: 800m (10min) | Light: 1600m (20min)") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "map_pet_garden_buffers.png"), p_pet_buf,
       width = 12, height = 8, dpi = 300)

# ============================================================================
# 5. Pet Garden Equity Analysis
# ============================================================================
cat("\n--- Equity Analysis ---\n")

# Scatter: aging ratio vs pet gardens
p_equity1 <- pet_per_district %>%
  ggplot(aes(x = aging_ratio, y = pet_gardens_per_100k, label = name)) +
  geom_point(aes(size = total_pop, color = public_housing_pct), alpha = 0.7) +
  geom_text(nudge_y = 0.3, size = 3, check_overlap = TRUE) +
  geom_smooth(method = "lm", se = TRUE, color = "red", linetype = "dashed") +
  scale_color_viridis_c(option = "C", name = "Public Housing %") +
  labs(title = "Aging Population vs Pet Garden Access",
       subtitle = "Do elderly-dense districts have adequate pet garden provision?",
       x = "Aging Ratio (65+ proportion)", y = "Pet Gardens per 100k") +
  theme_hk

ggsave(file.path(dir_figures, "scatter_aging_vs_pet.png"), p_equity1,
       width = 10, height = 7, dpi = 300)

# Scatter: population density vs pet gardens
p_equity2 <- pet_per_district %>%
  ggplot(aes(x = pop_density, y = n_pet_gardens, label = name)) +
  geom_point(aes(size = total_pop), color = "darkred", alpha = 0.7) +
  geom_text(nudge_y = 0.5, size = 3, check_overlap = TRUE) +
  geom_smooth(method = "lm", se = TRUE, color = "blue", linetype = "dashed") +
  labs(title = "Population Density vs Number of Pet Gardens",
       x = "Population Density (per km²)", y = "Number of Pet Gardens") +
  theme_hk

ggsave(file.path(dir_figures, "scatter_popdens_vs_pet.png"), p_equity2,
       width = 10, height = 7, dpi = 300)

# ============================================================================
# 6. Gap Analysis - Underserved Areas
# ============================================================================
cat("\n--- Gap Analysis: Underserved Districts ---\n")

# Define "underserved": high population but few/no pet gardens
pet_per_district <- pet_per_district %>%
  mutate(
    pop_rank = rank(-total_pop),
    pet_rank = rank(-n_pet_gardens),
    gap_score = pop_rank - pet_rank  # positive = more people than pet gardens
  )

cat("Gap Analysis (positive = underserved relative to population):\n")
print(pet_per_district %>%
        select(name, total_pop, n_pet_gardens, gap_score) %>%
        arrange(desc(gap_score)))

# Gap map
master_wgs$gap_score <- pet_per_district$gap_score[
  match(master_wgs$name, pet_per_district$name)
]

p_gap <- ggplot(master_wgs) +
  geom_sf(aes(fill = gap_score), color = "white", size = 0.5) +
  scale_fill_gradient2(low = "green", mid = "lightyellow", high = "red",
                        midpoint = 0, name = "Gap Score") +
  geom_sf_text(aes(label = name), size = 2.5) +
  labs(title = "Pet Garden Gap Analysis",
       subtitle = "Red = underserved (high pop, few pet gardens) | Green = well-served") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "map_pet_gap_analysis.png"), p_gap,
       width = 12, height = 8, dpi = 300)

# ============================================================================
# 7. Save Results
# ============================================================================
save(pet_per_district, ce_test, K_pet, L_pet,
     file = file.path(dir_output, "pet_garden_results.RData"))

cat("\n=== Pet Garden Analysis Complete! ===\n")
