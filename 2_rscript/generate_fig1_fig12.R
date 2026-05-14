# Generate fig1-fig12 for paper and dashboard usage.

required_pkgs <- c(
  "dplyr", "tidyr", "readr", "ggplot2", "patchwork", "maps", "scales",
  "WDI", "gganimate", "gifski", "spdep", "gridExtra", "ggalluvial", "circlize",
  "MASS", "rnaturalearth", "rnaturalearthdata", "openxlsx"
)

install_if_missing <- function(pkgs) {
  missing <- pkgs[!pkgs %in% rownames(installed.packages())]
  if (length(missing) > 0) {
    install.packages(missing, repos = "https://cloud.r-project.org")
  }
}
install_if_missing(required_pkgs)
invisible(lapply(required_pkgs, library, character.only = TRUE))

# Global: center all plot titles and subtitles
theme_update(
  plot.title = element_text(hjust = 0.5),
  plot.subtitle = element_text(hjust = 0.5)
)

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_dir <- if (length(file_arg) > 0) dirname(normalizePath(sub("^--file=", "", file_arg))) else getwd()
root_dir <- normalizePath(file.path(script_dir, ".."))

master_path <- file.path(script_dir, "data_parks_master.csv")
ind_path    <- file.path(script_dir, "data_indicators_master.csv")

if (!file.exists(master_path)) stop("Missing file: ", master_path)
if (!file.exists(ind_path)) stop("Missing file: ", ind_path)

master <- readr::read_csv(master_path, show_col_types = FALSE)
ind <- readr::read_csv(ind_path, show_col_types = FALSE)

master <- master %>%
  mutate(
    iso2c = country_code,
    parks_per_100k = as.numeric(parks_per_100k),
    n_parks = as.numeric(n_parks),
    park_density_score = as.numeric(park_density_score),
    dog_park_access_score = as.numeric(dog_park_access_score),
    avg_lat = as.numeric(avg_lat),
    avg_lon = as.numeric(avg_lon),
    global_percentile = as.numeric(global_percentile)
  )

ind <- ind %>%
  mutate(
    iso2c = iso2c,
    forest_cover_pct = as.numeric(forest_cover_pct),
    urban_pop_pct = as.numeric(urban_pop_pct),
    elderly_ratio = as.numeric(elderly_ratio),
    gdp_per_capita = as.numeric(gdp_per_capita),
    livability_index = as.numeric(livability_index),
    longitude = as.numeric(longitude),
    latitude = as.numeric(latitude)
  )

world <- ggplot2::map_data("world")

world_sf <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf")

base_world <- ggplot() +
  geom_polygon(data = world, aes(x = long, y = lat, group = group), fill = "grey95", color = "grey75", linewidth = 0.15) +
  coord_quickmap() +
  theme_void()

# Right panels: coord_sf with Mercator-like CRS, tightly cropped so the
# small panels are filled as much as possible without distortion.
base_world_right <- ggplot() +
  geom_sf(data = world_sf, fill = "grey95", color = "grey75", linewidth = 0.15) +
  coord_sf(xlim = c(-140, 155), ylim = c(-45, 72), expand = FALSE) +
  theme_void()

# Min-max normalizer for composite index construction.
norm01 <- function(x, reverse = FALSE) {
  rng <- range(x, na.rm = TRUE)
  if (!is.finite(rng[1]) || !is.finite(rng[2]) || (rng[2] - rng[1]) == 0) {
    out <- rep(NA_real_, length(x))
  } else {
    out <- (x - rng[1]) / (rng[2] - rng[1])
  }
  if (reverse) out <- 1 - out
  out
}

fig1_df <- ind %>%
  left_join(
    master %>% dplyr::select(iso2c, dog_park_access_score) %>% distinct(),
    by = "iso2c"
  ) %>%
  mutate(
    livability_4d = 100 * (
      0.25 * norm01(forest_cover_pct) +
      0.25 * norm01(urban_pop_pct) +
      0.25 * norm01(gdp_per_capita) +
      0.25 * norm01(elderly_ratio, reverse = TRUE)
    )
  )

# fig1 map panel
p_left_top <- base_world +
  geom_point(data = fig1_df, aes(x = longitude, y = latitude, color = livability_4d), size = 1.9, alpha = 0.86) +
  scale_color_viridis_c(option = "C", na.value = "grey70") +
  labs(title = "Composite Livability (4 Indicators)", color = "Index") +
  theme(plot.title = element_text(size = 15, face = "bold", hjust = 0.5))

p_left_bottom <- base_world +
  geom_point(data = fig1_df, aes(x = longitude, y = latitude, color = dog_park_access_score), size = 1.9, alpha = 0.86) +
  scale_color_viridis_c(option = "plasma", na.value = "grey70") +
  labs(title = "Dog Park Access Score", color = "Score") +
  theme(plot.title = element_text(size = 15, face = "bold", hjust = 0.5))

right_map_theme <- theme(
  legend.position = "bottom",
  legend.direction = "horizontal",
  legend.title = element_text(size = 9),
  legend.text = element_text(size = 8),
  plot.title = element_text(size = 12, face = "bold", hjust = 0.5),
  plot.margin = margin(2, 2, 2, 2)
)

p_right_1 <- base_world_right +
  geom_point(data = fig1_df, aes(x = longitude, y = latitude, color = forest_cover_pct), size = 1.25, alpha = 0.82) +
  scale_color_viridis_c(option = "D", na.value = "grey70") +
  labs(title = "Forest Cover (%)", color = "%") +
  guides(color = guide_colorbar(barwidth = grid::unit(3.1, "cm"), barheight = grid::unit(0.2, "cm"), title.position = "left")) +
  right_map_theme

p_right_2 <- base_world_right +
  geom_point(data = fig1_df, aes(x = longitude, y = latitude, color = elderly_ratio), size = 1.25, alpha = 0.82) +
  scale_color_viridis_c(option = "B", na.value = "grey70") +
  labs(title = "Elderly Ratio (%)", color = "%") +
  guides(color = guide_colorbar(barwidth = grid::unit(3.1, "cm"), barheight = grid::unit(0.2, "cm"), title.position = "left")) +
  right_map_theme

p_right_3 <- base_world_right +
  geom_point(data = fig1_df, aes(x = longitude, y = latitude, color = urban_pop_pct), size = 1.25, alpha = 0.82) +
  scale_color_viridis_c(option = "A", na.value = "grey70") +
  labs(title = "Urbanization (%)", color = "%") +
  guides(color = guide_colorbar(barwidth = grid::unit(3.1, "cm"), barheight = grid::unit(0.2, "cm"), title.position = "left")) +
  right_map_theme

p_right_4 <- base_world_right +
  geom_point(data = fig1_df, aes(x = longitude, y = latitude, color = gdp_per_capita), size = 1.25, alpha = 0.82) +
  scale_color_viridis_c(option = "magma", na.value = "grey70", labels = scales::label_number(scale_cut = scales::cut_short_scale())) +
  labs(title = "GDP per Capita (USD)", color = "USD") +
  guides(color = guide_colorbar(barwidth = grid::unit(3.1, "cm"), barheight = grid::unit(0.2, "cm"), title.position = "left")) +
  right_map_theme

left_block <- (p_left_top / p_left_bottom) + patchwork::plot_layout(heights = c(1, 1))
right_block <- (p_right_1 / p_right_2 / p_right_3 / p_right_4) +
  patchwork::plot_layout(heights = c(1, 1, 1, 1))

fig1 <- (left_block | right_block) +
  patchwork::plot_layout(widths = c(1, 1), heights = c(1, 1)) +
  patchwork::plot_annotation(
    title = "Global Six-Indicator Map Panel",
    subtitle = "Composite Livability is computed from forest, urbanization, GDP per capita, and inverse elderly ratio",
    theme = theme(
      plot.title = element_text(size = 22, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 11, hjust = 0.5)
    )
  )

ggsave(file.path(script_dir, "fig1_map_panel.png"), fig1, width = 18, height = 14, dpi = 320)

# fig2 hotspot strength map
pts_path <- file.path(root_dir, "3_html", "dashboard", "pet_parks_by_country.csv")
pts <- readr::read_csv(pts_path, show_col_types = FALSE) %>%
  mutate(longitude = as.numeric(longitude), latitude = as.numeric(latitude)) %>%
  filter(!is.na(longitude), !is.na(latitude), longitude >= -180, longitude <= 180, latitude >= -60, latitude <= 85)

kd <- MASS::kde2d(pts$longitude, pts$latitude, n = 320, lims = c(-180, 180, -60, 85))
dens_df <- expand.grid(lon = kd$x, lat = kd$y)
dens_df$density <- as.vector(kd$z)

pts_sample <- pts %>% slice_sample(n = min(2500, nrow(pts)))

fig2 <- ggplot() +
  geom_sf(data = world_sf, fill = "#f8fafc", color = "#b6c2cf", linewidth = 0.22) +
  geom_raster(data = dens_df, aes(x = lon, y = lat, fill = density), alpha = 0.75, interpolate = TRUE) +
  scale_fill_gradientn(
    colours = c("#edf4fb", "#c6dbef", "#9ecae1", "#6baed6", "#3182bd", "#08519c"),
    name = "Kernel density"
  ) +
  geom_point(
    data = pts_sample,
    aes(x = longitude, y = latitude),
    color = "#cc2f3b", size = 0.45, alpha = 0.26
  ) +
  coord_sf(xlim = c(-180, 180), ylim = c(-60, 85), expand = FALSE) +
  labs(
    title = "Global Kernel Density of Dog Parks",
    subtitle = "OpenStreetMap dog-park points (global perspective)",
    caption = "Projection: WGS84. Red points show sampled park locations."
  ) +
  theme_minimal(base_size = 15) +
  theme(
    panel.background = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA),
    panel.grid = element_blank(),
    axis.text = element_blank(),
    axis.title = element_blank(),
    legend.position = "right",
    legend.text = element_text(color = "#1f2937", size = 13),
    legend.title = element_text(color = "#111827", size = 14, face = "bold"),
    plot.title = element_text(color = "#111827", size = 24, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(color = "#334155", size = 15, hjust = 0.5),
    plot.caption = element_text(color = "#64748b", size = 12, hjust = 0.5),
    plot.margin = margin(16, 16, 16, 16)
  )

ggsave(file.path(script_dir, "fig2_map_dog_park.png"), fig2, width = 15.5, height = 8.8, dpi = 320)

# fig3 statistical distribution collage (unified style)
base_stat_theme <- theme_minimal(base_size = 15) +
  theme(
    panel.grid.minor = element_blank(),
    plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
    axis.title = element_text(size = 13),
    axis.text = element_text(size = 12),
    legend.position = "none"
  )

hist_age <- ggplot(ind, aes(x = elderly_ratio)) +
  geom_histogram(bins = 24, fill = "#2f6690", color = "white", alpha = 0.9) +
  labs(title = "Elderly Ratio Distribution", x = "Elderly ratio (%)", y = "Count") +
  base_stat_theme

forest_bar <- master %>%
  left_join(ind %>% dplyr::select(iso2c, forest_cover_pct), by = "iso2c") %>%
  group_by(region) %>%
  summarise(forest = mean(forest_cover_pct, na.rm = TRUE), .groups = "drop") %>%
  filter(!is.na(forest)) %>%
  ggplot(aes(x = reorder(region, forest), y = forest)) +
  geom_col(fill = "#3a7ca5", alpha = 0.9) +
  coord_flip() +
  labs(title = "Avg Forest Cover by Region", x = NULL, y = "Forest cover (%)") +
  base_stat_theme

gdp_bar <- master %>%
  left_join(ind %>% dplyr::select(iso2c, gdp_per_capita), by = "iso2c") %>%
  group_by(region) %>%
  summarise(gdp = mean(gdp_per_capita, na.rm = TRUE), .groups = "drop") %>%
  filter(!is.na(gdp)) %>%
  ggplot(aes(x = reorder(region, gdp), y = gdp)) +
  geom_col(fill = "#e07b39", alpha = 0.9) +
  coord_flip() +
  scale_y_continuous(labels = scales::label_number(scale_cut = scales::cut_short_scale())) +
  labs(title = "Avg GDP per Capita by Region", x = NULL, y = "GDP per capita (USD)") +
  base_stat_theme

urban_hist <- ggplot(ind, aes(x = urban_pop_pct)) +
  geom_histogram(bins = 24, fill = "#81b29a", color = "white", alpha = 0.92) +
  labs(title = "Urbanization Distribution", x = "Urbanization (%)", y = "Count") +
  base_stat_theme

parks_region <- master %>%
  group_by(region) %>%
  summarise(total_parks = sum(n_parks, na.rm = TRUE), .groups = "drop") %>%
  ggplot(aes(x = reorder(region, total_parks), y = total_parks)) +
  geom_col(fill = "#c97c5d", alpha = 0.9) +
  coord_flip() +
  labs(title = "Dog Parks by Region", x = NULL, y = "Total parks") +
  base_stat_theme

region_share <- master %>%
  count(region, name = "n") %>%
  mutate(pct = n / sum(n)) %>%
  ggplot(aes(x = reorder(region, pct), y = pct)) +
  geom_col(fill = "#6d597a", alpha = 0.9) +
  coord_flip() +
  scale_y_continuous(labels = scales::label_percent()) +
  labs(title = "Regional Country Share", x = NULL, y = "Share") +
  base_stat_theme

fig3 <- (hist_age + forest_bar + urban_hist) / (gdp_bar + parks_region + region_share) +
  patchwork::plot_annotation(
    title = "Statistical Distribution Overview",
    theme = theme(plot.title = element_text(size = 24, face = "bold", hjust = 0.5))
  )

ggsave(file.path(script_dir, "fig3_statistical_distribution.png"), fig3, width = 18, height = 11.5, dpi = 320)

# fig4 cluster nation
fig4 <- ind %>%
  filter(!is.na(urban_pop_pct), !is.na(elderly_ratio), !is.na(development_tier)) %>%
  ggplot(aes(x = urban_pop_pct, y = elderly_ratio, color = development_tier)) +
  geom_point(alpha = 0.8, size = 2) +
  stat_ellipse(linewidth = 0.9, linetype = 2, alpha = 0.6) +
  labs(
    title = "National Development Cluster Pattern",
    x = "Urbanization (%)",
    y = "Elderly ratio (%)",
    color = "Development tier"
  ) +
  theme_minimal(base_size = 15) +
  theme(plot.title = element_text(size = 22, face = "bold", hjust = 0.5), legend.position = "bottom")

ggsave(file.path(script_dir, "fig4_cluster_nation.png"), fig4, width = 12, height = 8, dpi = 300)

# tab1 three-line table (no image)
tab_df <- master %>%
  dplyr::select(country_name, n_parks, parks_per_100k, park_density_score, global_percentile, dog_park_access_score, cluster) %>%
  arrange(desc(parks_per_100k)) %>%
  slice_head(n = 25) %>%
  mutate(
    parks_per_100k = round(parks_per_100k, 2),
    park_density_score = round(park_density_score, 2),
    global_percentile = round(global_percentile, 1),
    dog_park_access_score = round(dog_park_access_score, 2)
  )

tab_xlsx <- file.path(script_dir, "tab1_country_comparison_three_line_table.xlsx")
wb_tbl <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb_tbl, "Table")
openxlsx::writeData(wb_tbl, "Table", tab_df, startRow = 1, withFilter = FALSE)

header_style <- openxlsx::createStyle(textDecoration = "bold", halign = "center", border = "topBottom")
body_style <- openxlsx::createStyle()
bottom_style <- openxlsx::createStyle(border = "bottom")

openxlsx::addStyle(wb_tbl, "Table", header_style, rows = 1, cols = 1:ncol(tab_df), gridExpand = TRUE)
openxlsx::addStyle(wb_tbl, "Table", body_style, rows = 2:nrow(tab_df), cols = 1:ncol(tab_df), gridExpand = TRUE, stack = TRUE)
openxlsx::addStyle(wb_tbl, "Table", bottom_style, rows = nrow(tab_df) + 1, cols = 1:ncol(tab_df), gridExpand = TRUE, stack = TRUE)
openxlsx::setColWidths(wb_tbl, "Table", cols = 1:ncol(tab_df), widths = "auto")
openxlsx::saveWorkbook(wb_tbl, tab_xlsx, overwrite = TRUE)

# Remove old figure output intentionally.
old_tab1 <- file.path(script_dir, "fig5_country_comparison.png")
if (file.exists(old_tab1)) file.remove(old_tab1)

# fig6 removed per latest request (delete if exists)
old_fig6 <- file.path(script_dir, "fig6_heatmap_accessibility.png")
if (file.exists(old_fig6)) file.remove(old_fig6)

# fig5 hotspot coldspot (local Gi*)
coords <- master %>%
  filter(!is.na(avg_lon), !is.na(avg_lat), !is.na(parks_per_100k)) %>%
  dplyr::select(country_name, avg_lon, avg_lat, parks_per_100k)

k_val <- max(4, min(8, nrow(coords) - 1))
knn <- spdep::knearneigh(as.matrix(coords[, c("avg_lon", "avg_lat")]), k = k_val)
nb <- spdep::knn2nb(knn)
lw <- spdep::nb2listw(nb, style = "W")

coords$gi <- as.numeric(spdep::localG(coords$parks_per_100k, lw))
coords$gi_class <- dplyr::case_when(
  coords$gi >= 1.96 ~ "Hot Spot",
  coords$gi <= -1.96 ~ "Cold Spot",
  TRUE ~ "Not Significant"
)

fig7 <- base_world +
  theme_void()

master_gi <- master %>%
  dplyr::select(country_code, parks_per_100k, avg_lon, avg_lat) %>%
  filter(!is.na(country_code), !is.na(parks_per_100k), !is.na(avg_lon), !is.na(avg_lat))

coords_gi <- as.matrix(master_gi[, c("avg_lon", "avg_lat")])
k_val <- max(4, min(8, nrow(master_gi) - 1))
knn <- spdep::knearneigh(coords_gi, k = k_val)
nb <- spdep::knn2nb(knn)
lw <- spdep::nb2listw(nb, style = "W")
master_gi$gi <- as.numeric(spdep::localG(master_gi$parks_per_100k, lw))
master_gi$gi_class <- dplyr::case_when(
  master_gi$gi >= 1.96 ~ "Hot Spot",
  master_gi$gi <= -1.96 ~ "Cold Spot",
  TRUE ~ "Not Significant"
)

world_gi <- world_sf %>%
  mutate(country_code = as.character(iso_a2)) %>%
  left_join(master_gi %>% dplyr::select(country_code, gi, gi_class), by = "country_code")

fig7 <- ggplot() +
  geom_sf(data = world_gi, aes(fill = gi_class), color = "#d1d5db", linewidth = 0.15) +
  scale_fill_manual(
    values = c("Hot Spot" = "#cb181d", "Cold Spot" = "#2171b5", "Not Significant" = "#d9d9d9"),
    drop = FALSE,
    name = "Gi* class"
  ) +
  coord_sf(xlim = c(-180, 180), ylim = c(-60, 85), expand = FALSE) +
  labs(
    title = "Global Getis-Ord Gi* Hotspot and Coldspot Map",
    subtitle = "Country-level parks_per_100k clustering significance (polygon classification)",
    caption = "Thresholds: z >= 1.96 (hot), z <= -1.96 (cold)."
  ) +
  theme_minimal(base_size = 15) +
  theme(
    panel.grid = element_blank(),
    axis.text = element_blank(),
    axis.title = element_blank(),
    legend.position = "right",
    plot.title = element_text(size = 24, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 15, hjust = 0.5),
    plot.caption = element_text(size = 12, color = "#64748b", hjust = 0.5),
    plot.margin = margin(16, 16, 16, 16)
  )

ggsave(file.path(script_dir, "fig5_hotspot_coldspot.png"), fig7, width = 15.5, height = 8.8, dpi = 320)

# fig6 correlation matrix heatmap
corr_df <- master %>%
  left_join(ind %>% dplyr::select(iso2c, forest_cover_pct, urban_pop_pct, elderly_ratio, livability_index, gdp_per_capita), by = "iso2c") %>%
  dplyr::select(dog_park_access_score, forest_cover_pct, urban_pop_pct, elderly_ratio, livability_index, gdp_per_capita) %>%
  mutate(across(everything(), as.numeric))

corr_mat <- cor(corr_df, use = "pairwise.complete.obs")

corr_long <- as.data.frame(as.table(corr_mat)) %>%
  rename(var1 = Var1, var2 = Var2, corr = Freq)

fig8 <- ggplot(corr_long, aes(x = var1, y = var2, fill = corr)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.2f", corr)), size = 5) +
  scale_fill_gradient2(low = "#2b8cbe", mid = "white", high = "#d7301f", midpoint = 0, limits = c(-1, 1)) +
  labs(title = "Correlation Matrix of Key Indicators", x = NULL, y = NULL, fill = "Correlation") +
  theme_minimal(base_size = 15) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 13), axis.text.y = element_text(size = 13), plot.title = element_text(size = 21, face = "bold", hjust = 0.5))

ggsave(file.path(script_dir, "fig6_corr_matrix.png"), fig8, width = 11, height = 9, dpi = 320)

# fig7 small-multiple faceted radar chart: one panel per top-10 country
radar_df <- master %>%
  left_join(ind %>% dplyr::select(iso2c, country, forest_cover_pct, urban_pop_pct, elderly_ratio), by = "iso2c") %>%
  mutate(country_name = coalesce(country_name, country)) %>%
  dplyr::select(country_name, parks_per_100k, dog_park_access_score,
                forest_cover_pct, urban_pop_pct, elderly_ratio) %>%
  filter(if_all(-country_name, ~ !is.na(.x))) %>%
  arrange(desc(parks_per_100k)) %>%
  slice_head(n = 10)

# Min-max normalise each metric across all 10 countries
radar_norm <- radar_df
for (j in 2:ncol(radar_norm)) {
  rng <- range(radar_norm[[j]], na.rm = TRUE)
  radar_norm[[j]] <- if (diff(rng) == 0) rep(0.5, nrow(radar_norm)) else
    (radar_norm[[j]] - rng[1]) / diff(rng)
}

# Readable axis labels
metric_labels <- c(
  parks_per_100k       = "Parks\n/100k",
  dog_park_access_score = "Access\nScore",
  forest_cover_pct     = "Forest\nCover",
  urban_pop_pct        = "Urban\nPop",
  elderly_ratio        = "Elderly\nRatio"
)

# Colour palette: one fixed colour per country (same order as data)
country_colors <- setNames(
  scales::hue_pal()(10),
  radar_norm$country_name
)

# Build long-format data and close each polygon by repeating the first metric
radar_long <- radar_norm %>%
  pivot_longer(cols = -country_name, names_to = "metric", values_to = "value") %>%
  mutate(
    metric = factor(metric, levels = names(metric_labels)),
    label  = metric_labels[as.character(metric)]
  )

# Close the polygon for each country panel
radar_closed <- bind_rows(
  radar_long,
  radar_long %>% filter(metric == levels(radar_long$metric)[1])
) %>%
  arrange(country_name, metric)

# Reference "full" polygon (value = 1 on every axis) for background shading
ref_poly <- expand.grid(
  country_name = unique(radar_closed$country_name),
  metric       = levels(radar_long$metric),
  stringsAsFactors = FALSE
) %>%
  mutate(value = 1, label = metric_labels[metric])
ref_poly <- bind_rows(
  ref_poly,
  ref_poly %>% filter(metric == levels(radar_long$metric)[1])
) %>%
  arrange(country_name, metric)

radar_plot <- ggplot(radar_closed, aes(x = metric, y = value, group = country_name)) +
  # Light grey filled reference polygon
  geom_polygon(data = ref_poly, aes(x = metric, y = value, group = country_name),
               fill = "grey92", color = NA, inherit.aes = FALSE) +
  # Grid circles at 0.25, 0.5, 0.75
  geom_hline(yintercept = c(0.25, 0.5, 0.75), color = "grey80", linewidth = 0.35, linetype = "dashed") +
  # Country polygon filled with its colour
  geom_polygon(aes(fill = country_name), alpha = 0.35, linewidth = 0.7, color = NA) +
  geom_path(aes(color = country_name), linewidth = 0.8) +
  geom_point(aes(color = country_name), size = 2.2) +
  scale_x_discrete(labels = metric_labels) +
  scale_y_continuous(limits = c(-0.1, 1.15), breaks = NULL, expand = c(0, 0)) +
  scale_color_manual(values = country_colors, guide = "none") +
  scale_fill_manual(values = country_colors, guide = "none") +
  coord_polar(start = 0) +
  facet_wrap(~ country_name, ncol = 5) +
  labs(title = "Radar Comparison: Top 10 Countries by Dog Park Access",
       subtitle = "Metrics normalised 0-1 within this group  |  Parks per 100k \u00b7 Access Score \u00b7 Forest Cover \u00b7 Urban Pop \u00b7 Elderly Ratio") +
  theme_minimal(base_size = 11) +
  theme(
    plot.title    = element_text(size = 16, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 9,  hjust = 0.5, color = "grey40"),
    strip.text    = element_text(size = 11, face = "bold"),
    axis.text.x   = element_text(size = 8, color = "grey30"),
    axis.text.y   = element_blank(),
    axis.title    = element_blank(),
    panel.grid.major = element_line(color = "grey85", linewidth = 0.3),
    panel.spacing = unit(0.8, "lines"),
    plot.margin   = margin(8, 8, 8, 8)
  )

ggsave(file.path(script_dir, "fig7_radar_top_countries.png"), radar_plot, width = 14, height = 7, dpi = 320)

# fig8 world bank animation + static
wb <- WDI::WDI(
  country = "all",
  indicator = c(
    forest_cover = "AG.LND.FRST.ZS",
    urbanization = "SP.URB.TOTL.IN.ZS",
    elderly_ratio = "SP.POP.65UP.TO.ZS",
    gdp_per_capita = "NY.GDP.PCAP.CD"
  ),
  start = 2000,
  end = 2024,
  extra = TRUE
)

wb2 <- wb %>%
  filter(region != "Aggregates") %>%
  transmute(region, year = as.integer(year), forest_cover, urbanization, elderly_ratio, gdp_per_capita) %>%
  group_by(region, year) %>%
  summarise(
    forest_cover = mean(forest_cover, na.rm = TRUE),
    urbanization = mean(urbanization, na.rm = TRUE),
    elderly_ratio = mean(elderly_ratio, na.rm = TRUE),
    gdp_per_capita = mean(gdp_per_capita, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_longer(cols = c(forest_cover, urbanization, elderly_ratio, gdp_per_capita), names_to = "indicator", values_to = "value") %>%
  filter(is.finite(value))

wb_labels <- c(
  forest_cover = "Forest Cover (% land)",
  urbanization = "Urbanization (% pop)",
  elderly_ratio = "Elderly Ratio (% 65+)",
  gdp_per_capita = "GDP per Capita (USD)"
)

fig10_base <- ggplot(wb2, aes(x = year, y = value, color = region, group = region)) +
  geom_line(linewidth = 1.2, alpha = 0.9) +
  geom_point(size = 2.1, alpha = 0.9) +
  facet_wrap(~ indicator, scales = "free_y", ncol = 2, labeller = as_labeller(wb_labels)) +
  scale_x_continuous(breaks = seq(2000, 2024, by = 4)) +
  labs(
    title = "Global Time Evolution of Key Indicators ({frame_along})",
    subtitle = "World Bank annual series, 2000-2024 (regional means)",
    x = "Year", y = "Value", color = "Region",
    caption = "Note: dog park currently snapshot-based (2023 static)."
  ) +
  theme_minimal(base_size = 19) +
  theme(
    plot.title = element_text(size = 28, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 18, hjust = 0.5),
    strip.text = element_text(size = 18, face = "bold"),
    axis.title = element_text(size = 17),
    axis.text = element_text(size = 14),
    legend.title = element_text(size = 15),
    legend.text = element_text(size = 13),
    legend.position = "bottom",
    legend.box = "horizontal",
    panel.grid.minor = element_blank(),
    plot.caption = element_text(size = 13)
  ) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE))

anim <- fig10_base + gganimate::transition_reveal(year)

gganimate::animate(
  anim,
  nframes = 150,
  fps = 10,
  width = 1800,
  height = 1200,
  renderer = gganimate::gifski_renderer(file.path(script_dir, "fig8_time_evolution.gif"))
)

fig10_static <- ggplot(wb2, aes(x = year, y = value, color = region, group = region)) +
  geom_line(linewidth = 1.4, alpha = 0.9) +
  geom_point(size = 2.3, alpha = 0.95) +
  facet_wrap(~ indicator, scales = "free_y", ncol = 2, labeller = as_labeller(wb_labels)) +
  scale_x_continuous(breaks = seq(2000, 2024, by = 4)) +
  labs(
    title = "Global Time Evolution of Key Indicators (2000-2024)",
    subtitle = "World Bank annual series, regional means",
    x = "Year", y = "Value", color = "Region",
    caption = "Note: dog park currently snapshot-based (2023 static)."
  ) +
  theme_minimal(base_size = 19) +
  theme(
    plot.title = element_text(size = 28, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 18, hjust = 0.5),
    strip.text = element_text(size = 18, face = "bold"),
    axis.title = element_text(size = 17),
    axis.text = element_text(size = 14),
    legend.title = element_text(size = 15),
    legend.text = element_text(size = 13),
    legend.position = "bottom",
    legend.box = "horizontal",
    panel.grid.minor = element_blank(),
    plot.caption = element_text(size = 13)
  ) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE))

ggsave(file.path(script_dir, "fig8_time_evolution_static.png"), fig10_static, width = 22, height = 14, dpi = 320)

# fig11 sankey-like alluvial
alluv <- master %>%
  mutate(cluster = ifelse(is.na(cluster) | cluster == "", "Unknown", cluster)) %>%
  count(development_level, tier, cluster, name = "n")

fig11 <- ggplot(alluv,
  aes(y = n, axis1 = development_level, axis2 = tier, axis3 = cluster)
) +
  ggalluvial::geom_alluvium(aes(fill = development_level), alpha = 0.8, width = 1/12) +
  ggalluvial::geom_stratum(width = 1/7, fill = "grey25", color = "white") +
  ggplot2::geom_text(stat = "stratum", aes(label = after_stat(stratum)), size = 5.1, color = "white") +
  scale_x_discrete(limits = c("Development Level", "Tier", "Cluster"), expand = c(0.05, 0.05)) +
  labs(title = "Sankey (Alluvial) Flow of Indicator Grouping", y = "Country count", x = NULL) +
  theme_minimal(base_size = 17) +
  theme(legend.position = "none", plot.title = element_text(size = 24, face = "bold", hjust = 0.5))

ggsave(file.path(script_dir, "fig9_sankey_indicator_flow.png"), fig11, width = 16, height = 8.5, dpi = 320)

# fig12 chord diagram – region-to-region peer links (readable version)
peer_regional <- master %>%
  dplyr::select(country_name, region, peer_1, peer_2, peer_3) %>%
  pivot_longer(cols = c(peer_1, peer_2, peer_3), names_to = "pr", values_to = "peer_name") %>%
  filter(!is.na(peer_name), country_name != peer_name, region != "", !is.na(region)) %>%
  left_join(
    master %>% dplyr::select(country_name, region) %>% rename(peer_region = region),
    by = c("peer_name" = "country_name")
  ) %>%
  filter(!is.na(peer_region)) %>%
  count(region, peer_region, name = "weight")

regions_all <- sort(unique(c(peer_regional$region, peer_regional$peer_region)))
n_reg <- length(regions_all)
reg_mat <- matrix(0, n_reg, n_reg, dimnames = list(regions_all, regions_all))
for (i in seq_len(nrow(peer_regional))) {
  r1 <- peer_regional$region[i]
  r2 <- peer_regional$peer_region[i]
  if (r1 %in% regions_all && r2 %in% regions_all) {
    reg_mat[r1, r2] <- reg_mat[r1, r2] + peer_regional$weight[i]
  }
}
reg_mat <- reg_mat + t(reg_mat)
diag(reg_mat) <- 0

region_colors <- colorRampPalette(
  c("#e41a1c", "#377eb8", "#4daf4a", "#984ea3", "#ff7f00", "#a65628", "#f781bf", "#999999")
)(n_reg)
names(region_colors) <- regions_all

png(file.path(script_dir, "fig10_chord_country_relation.png"), width = 2400, height = 2600, res = 280)
par(mar = c(2, 2, 5, 2), bg = "white")
circlize::circos.clear()
circlize::circos.par(gap.degree = 8, clock.wise = TRUE, start.degree = 90)
circlize::chordDiagram(
  reg_mat,
  grid.col = region_colors,
  transparency = 0.35,
  annotationTrack = c("name", "grid"),
  preAllocateTracks = list(track.height = 0.09),
  self.link = 1
)
title(
  "Cross-Regional Peer Linkage Chord Diagram\n(Country peer connections aggregated by World Bank region)",
  cex.main = 1.4, font.main = 2, col.main = "#1a1a2e", line = 1
)
dev.off()

message("All outputs generated in: ", script_dir)
