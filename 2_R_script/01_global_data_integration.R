# ============================================================================
# 01_global_data_integration.R
# Global Data Integration - Worldwide Dog Parks + World Indicators
# ============================================================================
# This script integrates:
#   1. Global dog park data from Python API collection
#   2. World Bank economic & development indicators
#   3. Geographic data and regional classification
#   4. Creates master global analysis dataset
# ============================================================================

source("00_setup.R")

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Global Data Integration Module\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# ============================================================================
# PART 1: Load Global Dog Park Data from Python Collection
# ============================================================================
cat("--- Loading Global Dog Park Data ---\n")

global_parks <- load_analysis_data("pet_parks_by_country_updated.csv")

if (!is.null(global_parks)) {
  cat(sprintf("✓ Loaded %d dog park records\n", nrow(global_parks)))
  cat(sprintf("  Countries represented: %d\n", n_distinct(global_parks$country_code)))

  # Aggregate by country
  parks_by_country <- global_parks %>%
    group_by(country_code, country_name) %>%
    summarise(
      n_parks = n(),
      n_nodes = sum(osm_type == "node", na.rm = TRUE),
      n_ways = sum(osm_type == "way", na.rm = TRUE),
      avg_lat = mean(latitude, na.rm = TRUE),
      avg_lon = mean(longitude, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(n_parks))

  cat("  Top 5 countries by dog parks:\n")
  print(head(parks_by_country %>% select(country_name, n_parks), 5))
  cat("\n")
}

# ============================================================================
# PART 2: Add Geographic and Regional Information
# ============================================================================
cat("--- Adding Geographic Information ---\n")

# First, add geographic info
parks_with_region <- parks_by_country %>%
  mutate(
    region = countrycode(country_code, origin = "iso2c", destination = "region"),
    continent = countrycode(country_code, origin = "iso2c", destination = "continent"),
    country_name_full = countrycode(country_code, origin = "iso2c", destination = "country.name")
  )

cat("✓ Geographic information added\n\n")

# ============================================================================
# Load REAL population data from World Bank (SP.POP.TOTL indicator)
# ============================================================================
cat("--- Fetching Real Population Data from World Bank ---\n")

# Try to get World Bank population data (2022 latest available)
tryCatch({
  # Download population data for all countries (SP.POP.TOTL = Total Population)
  wb_population <- WDI::WDI(
    indicator = "SP.POP.TOTL",
    country = "all",
    start = 2022,
    end = 2022,
    extra = FALSE
  ) %>%
    filter(!is.na(SP.POP.TOTL)) %>%
    mutate(iso2c = countrycode(country, origin = "country.name", destination = "iso2c")) %>%
    select(iso2c, year, population = SP.POP.TOTL) %>%
    filter(!is.na(iso2c))

  cat(sprintf("✓ Downloaded population data for %d countries from World Bank\n", n_distinct(wb_population$iso2c)))
  use_worldbank <- TRUE

}, error = function(e) {
  cat("⚠ World Bank data unavailable, using fallback estimates\n")
  cat("  Error:", conditionMessage(e), "\n")
  use_worldbank <<- FALSE
})

# Merge with geographic data
if (use_worldbank) {
  parks_with_region <- parks_with_region %>%
    left_join(
      wb_population %>% select(iso2c, population) %>% distinct(),
      by = c("country_code" = "iso2c")
    ) %>%
    mutate(
      # Use World Bank data, fall back to estimates if NA
      estimated_population = coalesce(
        population,
        case_when(
          country_code == "IN" ~ 1412e6,
          country_code == "CN" ~ 1425e6,
          country_code == "US" ~ 338e6,
          country_code == "ID" ~ 277e6,
          country_code == "BR" ~ 215e6,
          country_code == "GB" ~ 67e6,
          country_code == "FR" ~ 68e6,
          country_code == "DE" ~ 84e6,
          country_code == "JP" ~ 125e6,
          country_code == "HK" ~ 0.75e6,
          country_code == "SG" ~ 5.9e6,
          country_code == "AU" ~ 26e6,
          TRUE ~ 50e6
        )
      )
    )
} else {
  # No World Bank data, use all fallback estimates
  parks_with_region <- parks_with_region %>%
    mutate(
      estimated_population = case_when(
        country_code == "IN" ~ 1412e6,
        country_code == "CN" ~ 1425e6,
        country_code == "US" ~ 338e6,
        country_code == "ID" ~ 277e6,
        country_code == "BR" ~ 215e6,
        country_code == "GB" ~ 67e6,
        country_code == "FR" ~ 68e6,
        country_code == "DE" ~ 84e6,
        country_code == "JP" ~ 125e6,
        country_code == "HK" ~ 0.75e6,
        country_code == "SG" ~ 5.9e6,
        country_code == "AU" ~ 26e6,
        TRUE ~ 50e6
      )
    )
}

# Calculate metrics
parks_with_region <- parks_with_region %>%
  mutate(
    # Calculate dog parks per capita metric
    parks_per_100k = (n_parks / estimated_population) * 1e5,

    # Initial scoring
    park_density_score = standardize_to_100(parks_per_100k)
  ) %>%
  select(country_code, country_name, country_name_full, region, continent,
         n_parks, parks_per_100k, park_density_score, estimated_population, everything())

cat("✓ Geographic information added\n\n")

# ============================================================================
# PART 3: Regional Summary Statistics
# ============================================================================
cat("--- Regional Summary ---\n")

regional_summary <- parks_with_region %>%
  group_by(region) %>%
  summarise(
    n_countries = n(),
    total_parks = sum(n_parks),
    avg_parks_per_country = mean(n_parks),
    max_parks = max(n_parks),
    min_parks = min(n_parks),
    median_parks_per_100k = median(parks_per_100k, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(total_parks))

cat("Dog parks by region:\n")
print(regional_summary)
cat("\n")

# ============================================================================
# PART 4: Global Ranking
# ============================================================================
cat("--- Global Ranking Analysis ---\n")

global_ranking <- parks_with_region %>%
  mutate(
    # Calculate rank (1 = most parks per capita)
    global_rank = rank(-parks_per_100k),
    global_percentile = (n() - global_rank + 1) / n() * 100,

    # Tier classification
    tier = categorize_country(park_density_score)
  ) %>%
  arrange(global_rank)

cat(sprintf("✓ Global ranking for %d countries\n", nrow(global_ranking)))
cat("  Top 10 countries by dog parks per 100k:\n")
print(head(global_ranking %>% select(country_name, parks_per_100k, global_rank, tier), 10))
cat("\n")

# ============================================================================
# PART 5: Create Master Global Dataset
# ============================================================================
cat("--- Creating Master Global Dataset ---\n")

master_global <- global_ranking %>%
  mutate(
    # Composite livability indicator (based on park provision)
    # This will be expanded with additional indicators in later modules
    dog_park_access_score = park_density_score,

    # Development categorization (rough estimate)
    development_level = case_when(
      estimated_population > 100e6 & n_parks < 50 ~ "Developing",
      estimated_population > 100e6 & n_parks >= 50 ~ "Upper-Middle Income",
      estimated_population <= 100e6 & n_parks < 10 ~ "Low Income",
      estimated_population <= 100e6 & n_parks >= 10 ~ "High Income",
      TRUE ~ "Middle Income"
    ),

    analysis_year = ANALYSIS_YEAR,
    last_updated = Sys.Date()
  ) %>%
  arrange(global_rank)

cat("✓ Master global dataset created\n")
cat(sprintf("  Total countries: %d\n", nrow(master_global)))
cat(sprintf("  Total dog parks: %d\n", sum(master_global$n_parks)))
cat(sprintf("  Global average per 100k: %.2f\n", mean(master_global$parks_per_100k, na.rm = TRUE)))
cat("\n")

# ============================================================================
# PART 6: Save Processed Data
# ============================================================================
cat("--- Saving Processed Data ---\n")

# Save as RData
save(master_global, parks_with_region, regional_summary, global_ranking,
     file = file.path(dir_analysis, "01_master_global_data.RData"))

# Save as CSV for transparency
write_csv(master_global,
         file.path(dir_analysis, "01_master_global_dataset.csv"))

write_csv(regional_summary,
         file.path(dir_analysis, "01_regional_summary.csv"))

write_csv(global_ranking %>% select(country_name, n_parks, parks_per_100k,
                                    global_rank, global_percentile, tier, region),
         file.path(dir_analysis, "01_global_ranking.csv"))

cat("✓ Data saved successfully\n\n")

# ============================================================================
# Session Summary
# ============================================================================
cat("═══════════════════════════════════════════════════════════════\n")
cat("Global Data Integration Complete!\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Summary:\n")
cat(sprintf("  Countries analyzed: %d\n", nrow(master_global)))
cat(sprintf("  Total dog parks: %d\n", sum(master_global$n_parks)))
cat(sprintf("  Regions covered: %d\n", n_distinct(master_global$region)))
cat(sprintf("  Analysis year: %d\n\n", ANALYSIS_YEAR))

cat("Output files:\n")
cat("  ✓ 01_master_global_data.RData\n")
cat("  ✓ 01_master_global_dataset.csv\n")
cat("  ✓ 01_regional_summary.csv\n")
cat("  ✓ 01_global_ranking.csv\n\n")

cat("Next: Run 02_exploratory_analysis_global.R\n")
cat("═══════════════════════════════════════════════════════════════\n\n")
