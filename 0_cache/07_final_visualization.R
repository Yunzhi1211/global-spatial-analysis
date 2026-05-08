# ============================================================================
# 07_final_visualization.R
# Publication-Quality Maps & Summary Figures
# ============================================================================
# This script creates polished final maps for the project report:
#   1. Study area overview map
#   2. Multi-panel thematic atlas
#   3. Summary dashboard figure
#   4. Interactive web map (tmap view mode)
# ============================================================================

source("00_setup.R")
load(file.path(dir_output, "prepared_data.RData"))
load(file.path(dir_output, "accessibility_results.RData"))

# Fix geometries
master <- st_make_valid(master)
parks_combined <- st_make_valid(parks_combined)

# ============================================================================
# 1. Study Area Overview Map
# ============================================================================
cat("\n--- Creating Study Area Map ---\n")

master_wgs <- st_transform(master, wgs84) %>% st_make_valid() %>% st_cast("MULTIPOLYGON")
parks_wgs <- st_transform(parks_combined, wgs84) %>% st_make_valid()
hosp_wgs <- st_transform(hospitals, wgs84)
pet_wgs <- st_transform(pet_gardens, wgs84)

# Region classification for color
master_wgs <- master_wgs %>%
  mutate(region = case_when(
    name %in% c("Central and Western", "Wan Chai", "Eastern", "Southern") ~ "Hong Kong Island",
    name %in% c("Yau Tsim Mong", "Sham Shui Po", "Kowloon City",
                "Wong Tai Sin", "Kwun Tong") ~ "Kowloon",
    TRUE ~ "New Territories"
  ))

p_study_area <- ggplot() +
  geom_sf(data = master_wgs, aes(fill = region), alpha = 0.3, color = "grey40") +
  scale_fill_manual(values = c("Hong Kong Island" = "#e41a1c",
                                "Kowloon" = "#377eb8",
                                "New Territories" = "#4daf4a"),
                    name = "Region") +
  geom_sf(data = parks_wgs, fill = "darkgreen", alpha = 0.4, color = NA) +
  geom_sf(data = hosp_wgs, aes(shape = has_AE), color = "red", size = 2) +
  scale_shape_manual(values = c("Yes" = 17, "No" = 16), name = "A&E Service") +
  geom_sf(data = pet_wgs, color = "orange", size = 2.5, shape = 18) +
  geom_sf_text(data = master_wgs, aes(label = name),
               size = 2.2, color = "black", fontface = "bold") +
  labs(title = "Study Area: Hong Kong 18 Districts",
       subtitle = "Green = parks/green spaces | Red = hospitals | Orange = pet gardens",
       caption = "Data: OpenStreetMap, Hospital Authority, Census 2021") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 16),
        plot.subtitle = element_text(size = 11, color = "grey40"),
        legend.position = "right")

ggsave(file.path(dir_figures, "fig01_study_area.png"), p_study_area,
       width = 14, height = 9, dpi = 300)

# ============================================================================
# 2. Thematic Atlas (6-panel)
# ============================================================================
cat("\n--- Creating Thematic Atlas ---\n")

make_choro <- function(data, var, title, palette, style = "jenks") {
  ggplot(data) +
    geom_sf(aes(fill = .data[[var]]), color = "white", size = 0.3) +
    scale_fill_viridis_c(option = palette, name = NULL) +
    geom_sf_text(aes(label = name), size = 1.8, color = "grey20") +
    labs(title = title) +
    theme_void() +
    theme(plot.title = element_text(face = "bold", size = 10, hjust = 0.5),
          legend.key.size = unit(0.4, "cm"),
          legend.text = element_text(size = 7))
}

atlas_1 <- make_choro(master_wgs, "pop_density",
                       "A. Population Density (per km²)", "B")
atlas_2 <- make_choro(master_wgs, "aging_ratio",
                       "B. Aging Ratio (65+)", "D")
atlas_3 <- make_choro(master_wgs, "green_area_per_capita",
                       "C. Green Space Per Capita (m²)", "G")
atlas_4 <- make_choro(master_wgs, "hospitals_per_100k",
                       "D. Hospitals per 100k", "C")
atlas_5 <- make_choro(master_wgs, "healthcare_access_2sfca",
                       "E. Healthcare Access (2SFCA)", "E")
atlas_6 <- make_choro(master_wgs, "pet_gardens_per_100k",
                       "F. Pet Gardens per 100k", "A")

p_atlas <- (atlas_1 | atlas_2 | atlas_3) /
           (atlas_4 | atlas_5 | atlas_6) +
  plot_annotation(
    title = "Thematic Atlas: Urban Green Space and Population Health in Hong Kong",
    subtitle = "18 District Council Districts | Census 2021",
    theme = theme(plot.title = element_text(face = "bold", size = 16),
                  plot.subtitle = element_text(size = 12, color = "grey40"))
  )

ggsave(file.path(dir_figures, "fig02_thematic_atlas.png"), p_atlas,
       width = 18, height = 12, dpi = 300)

# ============================================================================
# 3. Key Findings Dashboard
# ============================================================================
cat("\n--- Creating Dashboard Figure ---\n")

# A. Green space inequality bar
p_dash_a <- master_wgs %>%
  st_drop_geometry() %>%
  mutate(name = reorder(name, green_area_per_capita)) %>%
  ggplot(aes(x = name, y = green_area_per_capita, fill = green_area_per_capita)) +
  geom_col(show.legend = FALSE) +
  scale_fill_viridis_c(option = "G", direction = -1) +
  coord_flip() +
  labs(title = "A. Green Space Per Capita", y = "m² per person", x = NULL) +
  theme_hk +
  theme(axis.text.y = element_text(size = 7))

# B. Scatter: pop density vs green space
p_dash_b <- master_wgs %>%
  st_drop_geometry() %>%
  ggplot(aes(x = pop_density, y = green_area_per_capita, label = name)) +
  geom_point(aes(color = aging_ratio, size = total_pop), alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE, color = "red", linetype = "dashed") +
  scale_color_viridis_c(option = "D", name = "Aging\nRatio") +
  scale_size_continuous(name = "Population", labels = scales::comma) +
  geom_text(nudge_y = 2, size = 2.5, check_overlap = TRUE) +
  labs(title = "B. Pop Density vs Green Space",
       x = "Pop Density (per km²)", y = "Green Space (m²/cap)") +
  theme_hk

# C. Hospital accessibility
p_dash_c <- master_wgs %>%
  st_drop_geometry() %>%
  ggplot(aes(x = reorder(name, healthcare_access_2sfca),
             y = healthcare_access_2sfca,
             fill = healthcare_access_2sfca)) +
  geom_col(show.legend = FALSE) +
  scale_fill_viridis_c(option = "C") +
  coord_flip() +
  labs(title = "C. Healthcare Accessibility (2SFCA)", y = "Index", x = NULL) +
  theme_hk +
  theme(axis.text.y = element_text(size = 7))

# D. Pet garden gap
p_dash_d <- master_wgs %>%
  st_drop_geometry() %>%
  ggplot(aes(x = total_pop, y = n_pet_gardens, label = name)) +
  geom_point(color = "darkred", size = 3, alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE, color = "blue", linetype = "dashed") +
  geom_text(nudge_y = 0.4, size = 2.5, check_overlap = TRUE) +
  labs(title = "D. Population vs Pet Gardens",
       x = "Total Population", y = "Number of Pet Gardens") +
  theme_hk

p_dashboard <- (p_dash_a | p_dash_b) / (p_dash_c | p_dash_d) +
  plot_annotation(
    title = "Key Findings: Urban Green Space & Health Equity in Hong Kong",
    theme = theme(plot.title = element_text(face = "bold", size = 16))
  )

ggsave(file.path(dir_figures, "fig03_dashboard.png"), p_dashboard,
       width = 18, height = 14, dpi = 300)

# ============================================================================
# 4. Interactive Map (HTML) - using leaflet directly (avoids tmap v3/v4 issues)
# ============================================================================
cat("\n--- Creating Interactive Map ---\n")

if (!require(leaflet)) install.packages("leaflet")
library(leaflet)

# Prepare popup text
master_wgs$popup_text <- paste0(
  "<b>", master_wgs$name, "</b><br>",
  "Population: ", format(master_wgs$total_pop, big.mark = ","), "<br>",
  "Pop Density: ", round(master_wgs$pop_density), " /km²<br>",
  "Green Spaces: ", master_wgs$n_green_spaces, "<br>",
  "Green m²/cap: ", round(master_wgs$green_area_per_capita, 1), "<br>",
  "Hospitals: ", master_wgs$n_hospitals, "<br>",
  "Pet Gardens: ", master_wgs$n_pet_gardens, "<br>",
  "Aging Ratio: ", round(master_wgs$aging_ratio, 3)
)

# Color palette
pal <- colorNumeric("YlGn", domain = master_wgs$green_area_per_capita)

imap <- leaflet() %>%
  addProviderTiles(providers$OpenStreetMap) %>%
  addPolygons(data = master_wgs,
              fillColor = ~pal(green_area_per_capita),
              fillOpacity = 0.6,
              color = "grey40", weight = 1.5,
              popup = ~popup_text,
              group = "Districts") %>%
  addCircleMarkers(data = hosp_wgs,
                   radius = 5,
                   color = ~ifelse(has_AE == "Yes", "red", "orange"),
                   fillOpacity = 0.8,
                   popup = ~paste0("<b>", name_eng, "</b><br>A&E: ", has_AE),
                   group = "Hospitals") %>%
  addCircleMarkers(data = pet_wgs,
                   radius = 5, color = "purple", fillOpacity = 0.8,
                   popup = ~paste0("<b>", name, "</b><br>", district),
                   group = "Pet Gardens") %>%
  addLegend(pal = pal, values = master_wgs$green_area_per_capita,
            title = "Green Space (m²/cap)") %>%
  addLayersControl(overlayGroups = c("Districts", "Hospitals", "Pet Gardens"))

htmlwidgets::saveWidget(imap, file.path(dir_figures, "interactive_map.html"),
                         selfcontained = TRUE)

cat("\n=== All Visualizations Complete! ===\n")
cat("Figures saved to:", dir_figures, "\n")
list.files(dir_figures) %>% cat(sep = "\n")
