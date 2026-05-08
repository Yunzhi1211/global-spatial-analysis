# ============================================================================
# 01_data_preparation.R
# Data loading, cleaning, spatial joining, and feature engineering
# ============================================================================
# This script:
#   1. Reads OSM shapefile and extracts parks/green spaces (using R sf package)
#   2. Reads 18-district boundaries
#   3. Reads and cleans census data (population, age, income, etc.)
#   4. Reads hospital and pet garden data
#   5. Performs spatial joins to aggregate everything by district
#   6. Creates the master analysis dataset
# ============================================================================

source("00_setup.R")

# ============================================================================
# PART 1: Extract Green Spaces from OSM Shapefile
# ============================================================================
cat("\n--- Reading OSM Shapefile (POIs - area features) ---\n")

# Read the POI area shapefile directly in R
pois_a <- st_read(file.path(osm_shp_dir, "gis_osm_pois_a_free_1.shp"))
cat("Total POI area features:", nrow(pois_a), "\n")
cat("Unique fclass values:\n")
print(sort(unique(pois_a$fclass)))

# Filter parks from POIs
parks_poi <- pois_a %>%
  filter(fclass %in% c("park", "garden", "playground", "dog_park",
                        "recreation_ground", "sports_centre", "pitch"))
cat("Parks/recreation from POIs:", nrow(parks_poi), "\n")

# Also read landuse layer for additional green spaces
cat("\n--- Reading OSM Shapefile (Landuse - area features) ---\n")
landuse_a <- st_read(file.path(osm_shp_dir, "gis_osm_landuse_a_free_1.shp"))
cat("Total landuse area features:", nrow(landuse_a), "\n")
cat("Unique fclass values:\n")
print(sort(unique(landuse_a$fclass)))

# Filter green/recreation landuse
green_landuse <- landuse_a %>%
  filter(fclass %in% c("park", "recreation_ground", "grass", "meadow",
                        "forest", "nature_reserve", "garden",
                        "village_green", "allotments"))
cat("Green landuse features:", nrow(green_landuse), "\n")

# Combine parks from both sources, keeping key columns
parks_combined <- bind_rows(
  parks_poi %>% select(osm_id, fclass, name) %>% mutate(source = "poi"),
  green_landuse %>% select(osm_id, fclass, name) %>% mutate(source = "landuse")
)

# Remove duplicates by osm_id
parks_combined <- parks_combined %>% distinct(osm_id, .keep_all = TRUE)
cat("\nCombined unique green spaces:", nrow(parks_combined), "\n")

# Ensure CRS is WGS84, then project to HK1980 for area calculation
parks_combined <- parks_combined %>%
  st_transform(wgs84) %>%
  st_make_valid()

# Save extracted green spaces to project data folder
st_write(parks_combined,
         file.path(dir_spatial, "green_spaces_osm.geojson"),
         delete_dsn = TRUE)
cat("Saved green_spaces_osm.geojson\n")

# ============================================================================
# PART 2: Read District Boundaries
# ============================================================================
cat("\n--- Reading 18 District Boundaries ---\n")
districts <- st_read(file.path(dir_spatial, "hk_18_districts.geojson")) %>%
  st_transform(wgs84) %>%
  st_make_valid()
cat("Districts loaded:", nrow(districts), "features\n")
print(districts$name)

# ============================================================================
# PART 3: Read and Clean Census Data
# ============================================================================
cat("\n--- Reading Census Data (DC_21C.xlsx) ---\n")

# Read Excel - skip header rows, use row 5 as column names
census_raw <- read_excel(file.path(dir_census, "DC_21C.xlsx"),
                         sheet = "DCD",
                         skip = 4) %>%
  clean_names()

# Preview structure
cat("Census dimensions:", dim(census_raw), "\n")

# Select key variables for analysis
# We need: district name, total population, age groups, median income, 
#           household count, education, etc.
census <- census_raw %>%
  filter(!is.na(dc_eng) & dc_eng != "") %>%
  select(
    district = dc_eng,
    # Population
    total_pop = t_pop,
    pop_male = pop_m,
    pop_female = pop_f,
    # Age groups
    age_under15 = age_1,        # <15
    age_15_24 = age_2,          # 15-24
    age_25_44 = age_3,          # 25-44
    age_45_64 = age_4,          # 45-64
    age_65plus = age_5,         # 65+
    median_age = t_ma,          # median age (total)
    # Ethnicity
    ethn_chinese = ethn_chi,
    # Education
    edu_degree = edu_deg,
    # Labour and Income
    labour_force = t_lf,
    # Households
    domestic_households = dh,
    # Housing tenure (public vs private)
    oq_public = oq_pub,
    oq_private = oq_pri
  ) %>%
  mutate(across(total_pop:oq_private, as.numeric))

# Calculate derived variables
census <- census %>%
  mutate(
    # Aging ratio: proportion aged 65+
    aging_ratio = age_65plus / total_pop,
    # Youth ratio: proportion under 15
    youth_ratio = age_under15 / total_pop,
    # Dependency ratio: (under 15 + 65+) / working age
    dependency_ratio = (age_under15 + age_65plus) / 
                       (age_15_24 + age_25_44 + age_45_64),
    # Education rate (degree holders per capita)
    degree_rate = edu_degree / total_pop,
    # Public housing proportion
    public_housing_pct = oq_public / (oq_public + oq_private)
  )

cat("Census cleaned:", nrow(census), "districts\n")
print(census %>% select(district, total_pop, aging_ratio) %>% arrange(desc(aging_ratio)))

# ============================================================================
# PART 4: Read Household Income Data (Table 130-06801)
# ============================================================================
cat("\n--- Reading Household Data ---\n")
hh_raw <- read_csv(file.path(dir_census, "Table 130-06801_en.csv"),
                    skip = 6, col_names = FALSE, show_col_types = FALSE)

# This table has household sizes by district; extract the latest year totals
# Structure: Year, DCD, then household counts by size
# We'll extract the most recent year's total households
# Parse the CSV more carefully
hh_data <- read_csv(file.path(dir_census, "Table 130-06801_en.csv"),
                    show_col_types = FALSE)

cat("Household data loaded.\n")

# ============================================================================
# PART 5: Read Hospital Data
# ============================================================================
cat("\n--- Reading Hospital Data ---\n")
hospitals <- st_read(file.path(dir_spatial, "hospitals.geojson")) %>%
  st_transform(wgs84)
cat("Hospitals loaded:", nrow(hospitals), "features\n")
cat("  With A&E:", sum(hospitals$has_AE == "Yes"), "\n")

# ============================================================================
# PART 6: Read Pet Garden Data
# ============================================================================
cat("\n--- Reading Pet Garden Data ---\n")
pet_gardens <- read_csv(file.path(dir_pet, "pet_gardens_hk.csv"),
                         show_col_types = FALSE) %>%
  st_as_sf(coords = c("lon", "lat"), crs = wgs84)
cat("Pet gardens loaded:", nrow(pet_gardens), "features\n")

# ============================================================================
# PART 7: Spatial Joins - Aggregate Everything by District
# ============================================================================
cat("\n--- Spatial Joins: Aggregating by District ---\n")

# Project everything to HK1980 for accurate area/distance calculations
districts_hk <- st_transform(districts, hk_crs)
parks_hk     <- st_transform(parks_combined, hk_crs) %>% st_make_valid()
hospitals_hk <- st_transform(hospitals, hk_crs)
pet_hk       <- st_transform(pet_gardens, hk_crs)

# 7a. Calculate district areas (km²)
districts_hk$area_km2 <- as.numeric(st_area(districts_hk)) / 1e6

# 7b. Green space per district
# Calculate area of each green space polygon
parks_hk$park_area_m2 <- as.numeric(st_area(parks_hk))

# Rename district name column to avoid conflict (parks also have 'name')
districts_hk_join <- districts_hk %>% rename(district_name = name)

# Spatial join: which parks fall in which district
parks_in_districts <- st_join(parks_hk, districts_hk_join["district_name"], left = FALSE)

green_by_district <- parks_in_districts %>%
  st_drop_geometry() %>%
  group_by(district_name) %>%
  summarise(
    n_green_spaces = n(),
    total_green_area_m2 = sum(park_area_m2, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  rename(name = district_name)

# 7c. Hospitals per district
hosp_in_districts <- st_join(hospitals_hk, districts_hk_join["district_name"], left = FALSE)
hosp_by_district <- hosp_in_districts %>%
  st_drop_geometry() %>%
  group_by(district_name) %>%
  summarise(
    n_hospitals = n(),
    n_ae_hospitals = sum(has_AE == "Yes", na.rm = TRUE),
    .groups = "drop"
  ) %>%
  rename(name = district_name)

# 7d. Pet gardens per district
pet_in_districts <- st_join(pet_hk, districts_hk_join["district_name"], left = FALSE)
pet_by_district <- pet_in_districts %>%
  st_drop_geometry() %>%
  group_by(district_name) %>%
  summarise(
    n_pet_gardens = n(),
    .groups = "drop"
  ) %>%
  rename(name = district_name)

# ============================================================================
# PART 8: Merge Everything into Master Dataset
# ============================================================================
cat("\n--- Building Master Dataset ---\n")

# Start with district geometries
master <- districts_hk %>%
  # Join census (match on district name)
  left_join(census, by = c("name" = "district")) %>%
  # Join green space stats
  left_join(green_by_district, by = "name") %>%
  # Join hospital stats
  left_join(hosp_by_district, by = "name") %>%
  # Join pet garden stats
  left_join(pet_by_district, by = "name")

# Fill NAs with 0 for count variables
master <- master %>%
  mutate(
    across(c(n_green_spaces, total_green_area_m2, 
             n_hospitals, n_ae_hospitals, n_pet_gardens),
           ~replace_na(., 0))
  )

# Calculate per-capita and density metrics
master <- master %>%
  mutate(
    # Population density (persons per km²)
    pop_density = total_pop / area_km2,
    
    # Green space metrics
    total_green_area_km2 = total_green_area_m2 / 1e6,
    green_space_pct = (total_green_area_km2 / area_km2) * 100,
    green_area_per_capita = total_green_area_m2 / total_pop,  # m² per person
    green_spaces_per_10k = (n_green_spaces / total_pop) * 10000,
    
    # Hospital accessibility proxy
    hospitals_per_100k = (n_hospitals / total_pop) * 100000,
    
    # Pet garden density
    pet_gardens_per_100k = (n_pet_gardens / total_pop) * 100000
  )

cat("Master dataset created:", nrow(master), "districts x", ncol(master), "variables\n")

# ============================================================================
# PART 9: Calculate Distance-Based Accessibility
# ============================================================================
cat("\n--- Calculating Distance-Based Accessibility ---\n")

# District centroids
centroids <- st_centroid(districts_hk)

# Distance from each district centroid to nearest hospital
nearest_hosp <- st_nearest_feature(centroids, hospitals_hk)
dist_to_nearest_hosp <- st_distance(centroids, hospitals_hk[nearest_hosp, ],
                                     by_element = TRUE)
master$dist_nearest_hospital_km <- as.numeric(dist_to_nearest_hosp) / 1000

# Distance to nearest A&E hospital
ae_hospitals <- hospitals_hk %>% filter(has_AE == "Yes")
nearest_ae <- st_nearest_feature(centroids, ae_hospitals)
dist_to_nearest_ae <- st_distance(centroids, ae_hospitals[nearest_ae, ],
                                   by_element = TRUE)
master$dist_nearest_ae_km <- as.numeric(dist_to_nearest_ae) / 1000

# Distance to nearest green space (centroid of nearest park)
park_centroids <- st_centroid(parks_hk)
nearest_park <- st_nearest_feature(centroids, park_centroids)
dist_to_nearest_park <- st_distance(centroids, park_centroids[nearest_park, ],
                                     by_element = TRUE)
master$dist_nearest_green_km <- as.numeric(dist_to_nearest_park) / 1000

# Distance to nearest pet garden
nearest_pet <- st_nearest_feature(centroids, pet_hk)
dist_to_nearest_pet <- st_distance(centroids, pet_hk[nearest_pet, ],
                                    by_element = TRUE)
master$dist_nearest_pet_km <- as.numeric(dist_to_nearest_pet) / 1000

cat("Distance metrics calculated.\n")

# ============================================================================
# PART 10: Save Master Dataset
# ============================================================================

# Save as GeoJSON (with geometry)
st_write(master, file.path(dir_output, "master_district_data.geojson"),
         delete_dsn = TRUE)

# Save as CSV (without geometry, for quick reference)
master %>%
  st_drop_geometry() %>%
  write_csv(file.path(dir_output, "master_district_data.csv"))

# Save key spatial objects for later scripts
save(master, parks_combined, parks_hk, hospitals, hospitals_hk,
     pet_gardens, pet_hk, districts, districts_hk, centroids,
     file = file.path(dir_output, "prepared_data.RData"))

cat("\n=== Data Preparation Complete! ===\n")
cat("Files saved to:", dir_output, "\n")
cat("  - master_district_data.geojson\n")
cat("  - master_district_data.csv\n")
cat("  - prepared_data.RData\n")

# Print summary
cat("\n--- Master Dataset Summary ---\n")
summary_df <- master %>%
  st_drop_geometry() %>%
  select(name, total_pop, pop_density, n_green_spaces, 
         green_area_per_capita, n_hospitals, n_pet_gardens) %>%
  arrange(desc(total_pop)) %>%
  as.data.frame()
print(summary_df)
