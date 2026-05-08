# ============================================================================
# 01_data_integration.R
# Data Integration: Python-collected Global Data + Local Hong Kong Data
# ============================================================================
# This script:
#   1. Loads global dog park data from Python API collection
#   2. Loads Hong Kong local datasets (census, spatial, health)
#   3. Integrates datasets for comparative analysis
#   4. Creates master analysis dataset
# ============================================================================

source("00_setup.R")

cat("\n===============================================\n")
cat("Data Integration Module\n")
cat("===============================================\n\n")

# ============================================================================
# PART 1: Load Global Dog Park Data from Python
# ============================================================================
cat("--- Loading Global Dog Park Data (from Python API) ---\n")

global_dog_parks <- load_analysis_data("pet_parks_by_country_updated.csv")

if (!is.null(global_dog_parks)) {
  cat(sprintf("✓ Loaded %d global dog park records\n", nrow(global_dog_parks)))
  cat(sprintf("  Countries covered: %d\n", n_distinct(global_dog_parks$country_code))
  cat("  Sample countries:", paste(head(unique(global_dog_parks$country_code), 5), collapse = ", "), "\n")
  
  # Aggregate global statistics by country
  global_dog_parks_by_country <- global_dog_parks %>%
    group_by(country_code, country_name) %>%
    summarise(
      n_dog_parks = n(),
      n_nodes = sum(osm_type == "node", na.rm = TRUE),
      n_ways = sum(osm_type == "way", na.rm = TRUE),
      avg_lat = mean(latitude, na.rm = TRUE),
      avg_lon = mean(longitude, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(n_dog_parks))
  
  # Calculate dog parks per capita (rough estimate using common population)
  global_dog_parks_by_country <- global_dog_parks_by_country %>%
    mutate(
      dog_parks_per_100k = case_when(
        country_code == "GB" ~ n_dog_parks / 6.7 * 1e5,
        country_code == "US" ~ n_dog_parks / 331 * 1e5,
        country_code == "CN" ~ n_dog_parks / 1412 * 1e5,
        country_code == "HK" ~ n_dog_parks / 0.75 * 1e5,
        country_code == "DE" ~ n_dog_parks / 83 * 1e5,
        country_code == "FR" ~ n_dog_parks / 68 * 1e5,
        country_code == "AU" ~ n_dog_parks / 26 * 1e5,
        country_code == "JP" ~ n_dog_parks / 125 * 1e5,
        TRUE ~ n_dog_parks / 50 * 1e5  # Default estimate
      )
    )
  
  cat("✓ Global dog parks aggregated by country\n\n")
}

# ============================================================================
# PART 2: Load Hong Kong District Spatial Data
# ============================================================================
cat("--- Loading Hong Kong 18 District Boundaries ---\n")

hk_districts <- load_spatial_data("hk_18_districts.geojson")

if (!is.null(hk_districts)) {
  hk_districts <- hk_districts %>%
    st_transform(wgs84) %>%
    st_make_valid()
  
  cat(sprintf("✓ Loaded %d districts\n", nrow(hk_districts)))
  print(hk_districts$name)
  cat("\n")
}

# ============================================================================
# PART 3: Load Hong Kong Census Data
# ============================================================================
cat("--- Loading Hong Kong Census Data ---\n")

census_data <- load_analysis_data("master_district_data.csv")

if (!is.null(census_data)) {
  cat(sprintf("✓ Loaded census data for %d districts\n", nrow(census_data)))
  cat("  Variables: ", paste(colnames(census_data), collapse = ", "), "\n")
  
  # Key demographic variables
  key_census_vars <- c("name", "total_pop", "pop_density", "aging_ratio",
                       "dependency_ratio", "median_age", "household_size")
  
  # Check which variables exist
  available_vars <- intersect(key_census_vars, colnames(census_data))
  cat(sprintf("  ✓ Found %d demographic variables\n\n", length(available_vars)))
}

# ============================================================================
# PART 4: Load Hong Kong Green Space Data
# ============================================================================
cat("--- Loading Hong Kong Green Space Data ---\n")

green_spaces_osm <- load_spatial_data("green_spaces_osm.geojson")

if (!is.null(green_spaces_osm)) {
  cat(sprintf("✓ Loaded %d green space features\n", nrow(green_spaces_osm)))
  cat("  Types: ", paste(unique(green_spaces_osm$fclass), collapse = ", "), "\n\n")
}

# ============================================================================
# PART 5: Load Hong Kong Health Facilities
# ============================================================================
cat("--- Loading Hong Kong Health Facilities ---\n")

# Check if health data exists
health_file <- file.path(dir_output, "ha_hospitals.json")
if (file.exists(health_file)) {
  hospitals_raw <- fromJSON(health_file)
  cat(sprintf("✓ Loaded hospital data\n\n"))
} else {
  cat("⚠ Hospital data not found - will create placeholder\n\n")
}

# ============================================================================
# PART 6: Create Master Analysis Dataset
# ============================================================================
cat("--- Creating Master Analysis Dataset ---\n")

# Merge census data with district boundaries
if (!is.null(hk_districts) && !is.null(census_data)) {
  
  # Join census data to spatial districts
  hk_master <- hk_districts %>%
    left_join(
      census_data %>% select(-geometry) %>% st_drop_geometry() %>% distinct(),
      by = c("name" = "name")
    ) %>%
    st_make_valid()
  
  cat("✓ Merged census data with district boundaries\n")
  
  # Calculate green space metrics by district
  if (!is.null(green_spaces_osm)) {
    green_by_district <- st_intersection(green_spaces_osm, hk_districts) %>%
      group_by(name) %>%
      summarise(
        n_green_spaces = n(),
        total_green_area_m2 = sum(st_area(.), na.rm = TRUE),
        .groups = "drop"
      ) %>%
      st_drop_geometry()
    
    hk_master <- hk_master %>%
      left_join(green_by_district, by = "name")
    
    cat("✓ Calculated green space metrics by district\n")
  }
  
  # Calculate green space indicators
  hk_master <- hk_master %>%
    mutate(
      # Green space metrics
      total_green_area_km2 = total_green_area_m2 / 1e6,
      green_area_per_capita = ifelse(total_pop > 0,
                                     total_green_area_m2 / total_pop, 0),
      green_space_pct = ifelse(st_area(.) > 0,
                               as.numeric(total_green_area_m2) / as.numeric(st_area(.)) * 100,
                               0),
      
      # Standardized indicators (0-100 scale)
      green_space_score = standardize_to_100(green_area_per_capita),
      population_density_score = 100 - standardize_to_100(log(pop_density + 1)),
      aging_ratio_score = 100 - standardize_to_100(aging_ratio),
      
      # District category
      district_type = case_when(
        pop_density > 10000 ~ "Very High Density",
        pop_density > 5000 ~ "High Density",
        pop_density > 2000 ~ "Medium Density",
        TRUE ~ "Low Density"
      ),
      
      # Analysis timestamp
      analysis_year = ANALYSIS_YEAR
    )
  
  cat("✓ Calculated standardized indicators (0-100 scale)\n")
  
  # Count dog parks in Hong Kong
  if (!is.null(global_dog_parks)) {
    hk_dog_parks <- global_dog_parks %>%
      filter(country_code == "HK") %>%
      st_as_sf(coords = c("longitude", "latitude"), crs = wgs84)
    
    if (nrow(hk_dog_parks) > 0) {
      dog_parks_by_district <- st_intersection(hk_dog_parks, hk_districts) %>%
        group_by(name) %>%
        summarise(
          n_dog_parks = n(),
          .groups = "drop"
        ) %>%
        st_drop_geometry()
      
      hk_master <- hk_master %>%
        left_join(dog_parks_by_district, by = "name") %>%
        mutate(n_dog_parks = coalesce(n_dog_parks, 0),
               dog_parks_per_100k = ifelse(total_pop > 0,
                                          n_dog_parks / total_pop * 1e5, 0))
      
      cat(sprintf("✓ Identified %d dog parks in Hong Kong\n", nrow(hk_dog_parks)))
    }
  }
  
  # Calculate composite health & livability score
  hk_master <- hk_master %>%
    mutate(
      # Composite scores
      environmental_score = (green_space_score + population_density_score) / 2,
      social_health_score = (aging_ratio_score + 
                            (100 - standardize_to_100(dependency_ratio))) / 2,
      
      # Overall livability score (preliminary)
      livability_score = (environmental_score * 0.4 +
                         social_health_score * 0.3 +
                         standardize_to_100(dog_parks_per_100k) * 0.15 +
                         100 - standardize_to_100(pop_density) * 0.15)
    )
  
  cat("✓ Calculated composite livability scores\n")
  
} else {
  cat("⚠ Cannot create master dataset - missing spatial or census data\n")
  hk_master <- NULL
}

# ============================================================================
# PART 7: Create Global Ranking Dataset
# ============================================================================
cat("\n--- Creating Global Ranking Dataset ---\n")

global_indicators <- global_dog_parks_by_country %>%
  mutate(
    # Standardize dog parks metric to 0-100
    dog_parks_score = standardize_to_100(dog_parks_per_100k),
    
    # Global rank
    global_rank = rank(-dog_parks_score),
    global_rank_pct = (n() - global_rank + 1) / n() * 100,
    
    # Category
    global_category = categorize_score(dog_parks_score)
  ) %>%
  arrange(global_rank)

cat(sprintf("✓ Created global ranking for %d countries\n", nrow(global_indicators)))

# Calculate Hong Kong's global position
if ("HK" %in% global_indicators$country_code) {
  hk_global_stats <- global_indicators %>% filter(country_code == "HK")
  cat(sprintf("  Hong Kong rank: %d/%d (%.1f percentile)\n",
              hk_global_stats$global_rank, nrow(global_indicators),
              hk_global_stats$global_rank_pct))
}

# ============================================================================
# PART 8: Save Processed Data
# ============================================================================
cat("\n--- Saving Processed Data ---\n")

# Save as RData for faster loading
save(hk_master, hk_districts, green_spaces_osm, 
     global_dog_parks_by_country, global_indicators,
     census_data, global_dog_parks,
     file = file.path(dir_analysis, "01_integrated_data.RData"))

# Save as CSV for transparency
if (!is.null(hk_master)) {
  write_csv(
    hk_master %>% st_drop_geometry(),
    file.path(dir_analysis, "hk_districts_analysis.csv")
  )
}

write_csv(global_indicators,
         file.path(dir_analysis, "global_dog_parks_ranking.csv"))

cat("✓ Data saved to analysis_results folder\n\n")

# ============================================================================
# Session Summary
# ============================================================================
cat("===============================================\n")
cat("Data Integration Complete!\n")
cat("===============================================\n")
cat("Master dataset dimensions:\n")
if (!is.null(hk_master)) {
  cat(sprintf("  Districts: %d\n", nrow(hk_master)))
  cat(sprintf("  Variables: %d\n", ncol(hk_master) - 1))  # Exclude geometry
  cat(sprintf("  Total population: %s\n", 
              format(sum(hk_master$total_pop, na.rm = TRUE), big.mark = ",")))
}
cat(sprintf("\nGlobal indicators:\n")
cat(sprintf("  Countries: %d\n", nrow(global_indicators)))
cat(sprintf("  Total dog parks: %d\n", sum(global_indicators$n_dog_parks)))

cat("\nNext step: Run 02_exploratory_analysis.R\n")
cat("===============================================\n\n")
