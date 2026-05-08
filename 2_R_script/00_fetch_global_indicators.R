# ============================================================================
# 00_fetch_global_indicators.R
# Global Urban Livability & Green Space Analysis - Comprehensive Data Fetching
# ============================================================================
# This script fetches comprehensive global indicators from World Bank API:
#   - Population & Demographics (total, urban, density)
#   - Age Structure (elderly ratio, youth dependency)
#   - Green Space & Environment (forest cover, urban green)
#   - Health Indicators (life expectancy, mortality)
#   - Economic Development (GDP, urbanization)
# ============================================================================

cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║     Global Urban Livability & Green Space Analysis             ║\n")
cat("║     Comprehensive World Bank Data Fetching                     ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# ============================================================================
# SETUP
# ============================================================================

required_packages <- c("wbstats", "tidyverse", "sf", "jsonlite", "countrycode")

for (pkg in required_packages) {
  if (!require(pkg, character.only = TRUE)) {
    cat(sprintf("Installing %s...\n", pkg))
    install.packages(pkg, quiet = TRUE)
    library(pkg, character.only = TRUE)
  }
}

cat("✓ All packages loaded\n\n")

# Directories
dir.create("../3_output/global_indicators", recursive = TRUE, showWarnings = FALSE)
output_dir <- "../3_output/global_indicators"

# ============================================================================
# STEP 1: Define All Indicators to Fetch
# ============================================================================

cat("--- STEP 1: Defining World Bank Indicators ---\n")

# Comprehensive indicator list (validated working indicators)
indicators <- c(
  # Demographics
  "SP.POP.TOTL",        # Total population
  "SP.POP.GROW",        # Population growth (annual %)
  "SP.URB.TOTL.IN.ZS",  # Urban population (% of total)
  "EN.POP.DNST",        # Population density (people per sq km)
  
  # Age Structure
  "SP.POP.65UP.TO.ZS",  # Population ages 65+ (% of total)
  "SP.POP.0014.TO.ZS",  # Population ages 0-14 (% of total)
  "SP.DYN.CDRT.IN",     # Death rate (crude, per 1000)
  "SP.DYN.LE00.IN",     # Life expectancy at birth (years)
  
  # Green Space & Environment
  "AG.LND.FRST.ZS",     # Forest area (% of land area)
  "AG.LND.AGRI.ZS",     # Agricultural land (% of land area)
  "AG.LND.TOTL.K2",     # Land area (sq km)
  "EN.ATM.CO2E.PC",     # CO2 emissions (metric tons per capita)
  
  # Health
  "SH.DYN.MORT",        # Mortality rate under-5 (per 1000 live births)
  "SH.XPD.CHEX.PC.CD",  # Health expenditure per capita (USD)
  "SH.MED.BEDS.ZS",     # Hospital beds (per 1000 people)
  
  # Economy & Development
  "NY.GDP.PCAP.CD",     # GDP per capita (current USD)
  "NY.GDP.PCAP.PP.CD",  # GDP per capita PPP (current international $)
  "SI.POV.GINI"         # GINI index
)

indicator_names <- c(
  "population", "pop_growth_pct", "urban_pop_pct", "pop_density",
  "elderly_ratio", "youth_ratio", "death_rate", "life_expectancy",
  "forest_cover_pct", "agri_land_pct", "land_area_km2", "co2_per_capita",
  "child_mortality", "health_expenditure", "hospital_beds",
  "gdp_per_capita", "gdp_ppp", "gini_index"
)

cat(sprintf("✓ Defined %d indicators to fetch\n\n", length(indicators)))

# ============================================================================
# STEP 2: Fetch All Indicators
# ============================================================================

cat("--- STEP 2: Fetching World Bank Data ---\n")

all_data <- list()

for (i in seq_along(indicators)) {
  ind <- indicators[i]
  name <- indicator_names[i]
  
  cat(sprintf("  [%d/%d] Fetching %s (%s)...", i, length(indicators), name, ind))
  
  tryCatch({
    # Try with simpler parameters
    data <- wb_data(
      indicator = ind,
      start_date = 2015,
      end_date = 2024,
      return_wide = FALSE
    ) %>%
      filter(!is.na(value)) %>%
      select(iso3c, iso2c, country, date, value) %>%
      group_by(iso3c) %>%
      slice_max(date, n = 1) %>%
      ungroup()
    
    names(data)[names(data) == "value"] <- name
    all_data[[name]] <- data %>% select(iso3c, country, !!sym(name))
    
    cat(sprintf(" ✓ %d countries\n", nrow(data)))
    
  }, error = function(e) {
    cat(sprintf(" ✗ Error: %s\n", substr(conditionMessage(e), 1, 80)))
    all_data[[name]] <<- tibble(iso3c = character(), country = character())
  })
  
  Sys.sleep(0.5)  # More conservative rate limiting
}

# ============================================================================
# STEP 3: Merge All Data
# ============================================================================

cat("\n--- STEP 3: Merging All Indicators ---\n")

# Get country reference with coordinates
countries_ref <- wb_countries() %>%
  filter(!is.na(longitude), !is.na(latitude)) %>%
  select(iso3c, iso2c, country, region, income_level, longitude, latitude)

# Start with reference, merge all indicators
master_global <- countries_ref

for (name in names(all_data)) {
  if (nrow(all_data[[name]]) > 0) {
    master_global <- master_global %>%
      left_join(
        all_data[[name]] %>% select(iso3c, !!sym(name)),
        by = "iso3c"
      )
  }
}

cat(sprintf("✓ Master dataset: %d countries x %d variables\n", 
            nrow(master_global), ncol(master_global)))

# ============================================================================
# STEP 4: Calculate Derived Indicators
# ============================================================================

cat("\n--- STEP 4: Calculating Derived Indicators ---\n")

# Check which columns exist
cols <- names(master_global)
has_elderly <- "elderly_ratio" %in% cols
has_youth <- "youth_ratio" %in% cols
has_forest <- "forest_cover_pct" %in% cols
has_urban <- "urban_pop_pct" %in% cols
has_life <- "life_expectancy" %in% cols
has_child_mort <- "child_mortality" %in% cols
has_co2 <- "co2_per_capita" %in% cols
has_gdp <- "gdp_per_capita" %in% cols

cat(sprintf("  Available columns: %d\n", length(cols)))

# Add derived indicators step by step
if (has_elderly && has_youth) {
  master_global <- master_global %>%
    mutate(
      working_age_ratio = 100 - elderly_ratio - youth_ratio,
      dependency_ratio = case_when(
        working_age_ratio > 0 ~ (youth_ratio + elderly_ratio) / working_age_ratio * 100,
        TRUE ~ NA_real_
      ),
      aging_index = case_when(
        youth_ratio > 0 ~ elderly_ratio / youth_ratio * 100,
        TRUE ~ NA_real_
      )
    )
  cat("  ✓ Age structure indicators\n")
}

if (has_forest) {
  master_global <- master_global %>%
    mutate(
      green_score = pmin(100, forest_cover_pct * 1.5)
    )
  cat("  ✓ Green space score\n")
}

if (has_urban) {
  master_global <- master_global %>%
    mutate(
      urbanization_level = case_when(
        urban_pop_pct >= 80 ~ "Highly Urban",
        urban_pop_pct >= 60 ~ "Urban",
        urban_pop_pct >= 40 ~ "Transitional",
        urban_pop_pct >= 20 ~ "Rural",
        TRUE ~ "Highly Rural"
      )
    )
  cat("  ✓ Urbanization level\n")
}

# Development tier (always available - uses income_level)
master_global <- master_global %>%
  mutate(
    development_tier = case_when(
      income_level == "High income" ~ "Developed",
      income_level == "Upper middle income" ~ "Emerging",
      income_level == "Lower middle income" ~ "Developing",
      income_level == "Low income" ~ "Least Developed",
      TRUE ~ "Unknown"
    )
  )
cat("  ✓ Development tier\n")

if (has_life) {
  if (has_child_mort) {
    master_global <- master_global %>%
      mutate(
        health_score = case_when(
          !is.na(life_expectancy) & !is.na(child_mortality) ~
            (life_expectancy / 85 * 50) + ((1 - pmin(child_mortality, 100)/100) * 50),
          !is.na(life_expectancy) ~ life_expectancy / 85 * 100,
          TRUE ~ NA_real_
        )
      )
  } else {
    master_global <- master_global %>%
      mutate(
        health_score = life_expectancy / 85 * 100
      )
  }
  cat("  ✓ Health score\n")
}

if (has_co2) {
  master_global <- master_global %>%
    mutate(
      env_pressure = pmin(100, co2_per_capita * 5)
    )
  cat("  ✓ Environmental pressure\n")
}

# Livability index (composite)
if (has_life && has_gdp && has_forest) {
  master_global <- master_global %>%
    mutate(
      livability_index = case_when(
        !is.na(health_score) & !is.na(gdp_per_capita) & !is.na(green_score) ~
          (health_score * 0.4 + 
           pmin(100, gdp_per_capita/1000) * 0.3 + 
           green_score * 0.3),
        TRUE ~ NA_real_
      )
    )
  cat("  ✓ Livability index\n")
}

cat("✓ Derived indicators calculated\n")

# ============================================================================
# STEP 5: Regional Aggregations
# ============================================================================

cat("\n--- STEP 5: Computing Regional Statistics ---\n")

# Estimate population if missing
if (!"population" %in% names(master_global)) {
  if ("pop_density" %in% names(master_global) && "land_area_km2" %in% names(master_global)) {
    master_global <- master_global %>%
      mutate(population = pop_density * land_area_km2)
    cat("  ✓ Estimated population from density × area\n")
  } else {
    # Create placeholder
    master_global$population <- NA_real_
  }
}

regional_stats <- master_global %>%
  filter(!is.na(region)) %>%
  group_by(region) %>%
  summarise(
    n_countries = n(),
    total_pop = sum(population, na.rm = TRUE),
    avg_elderly_ratio = mean(elderly_ratio, na.rm = TRUE),
    avg_youth_ratio = mean(youth_ratio, na.rm = TRUE),
    avg_life_expectancy = mean(life_expectancy, na.rm = TRUE),
    avg_gdp_per_capita = mean(gdp_per_capita, na.rm = TRUE),
    avg_pop_density = mean(pop_density, na.rm = TRUE),
    .groups = "drop"
  )

cat(sprintf("✓ Regional statistics for %d regions\n", nrow(regional_stats)))

# ============================================================================
# STEP 6: Save All Outputs
# ============================================================================

cat("\n--- STEP 6: Saving Outputs ---\n")

# Master dataset
write_csv(master_global, file.path(output_dir, "global_indicators_master.csv"))
cat("  ✓ global_indicators_master.csv\n")

# Regional stats
write_csv(regional_stats, file.path(output_dir, "regional_statistics.csv"))
cat("  ✓ regional_statistics.csv\n")

# JSON for dashboard - select only available columns
available_cols <- intersect(
  names(master_global),
  c("iso3c", "iso2c", "country", "region", "income_level",
    "longitude", "latitude", "population", "pop_density", "urban_pop_pct",
    "elderly_ratio", "youth_ratio", "life_expectancy",
    "forest_cover_pct", "gdp_per_capita", "health_score", "green_score",
    "urbanization_level", "development_tier", "livability_index")
)

master_json <- master_global %>%
  filter(!is.na(population) | !is.na(pop_density)) %>%
  select(all_of(available_cols)) %>%
  mutate(across(where(is.numeric), ~round(., 2)))

jsonlite::write_json(
  master_json, 
  file.path(output_dir, "global_indicators.json"),
  pretty = TRUE
)
cat("  ✓ global_indicators.json\n")

jsonlite::write_json(
  regional_stats %>% mutate(across(where(is.numeric), ~round(., 2))),
  file.path(output_dir, "regional_stats.json"),
  pretty = TRUE
)
cat("  ✓ regional_stats.json\n")

# Summary
cat("\n╔════════════════════════════════════════════════════════════════╗\n")
cat("║     Global Indicators Fetch Complete!                          ║\n")
cat("╠════════════════════════════════════════════════════════════════╣\n")
cat(sprintf("║  Countries: %d                                                ║\n", nrow(master_global)))
cat(sprintf("║  Variables: %d                                                ║\n", ncol(master_global)))
cat(sprintf("║  Regions:   %d                                                 ║\n", nrow(regional_stats)))
cat("╚════════════════════════════════════════════════════════════════╝\n")

# Print sample
cat("\n--- Sample Data (Top 10 by Life Expectancy) ---\n")
sample_cols <- intersect(names(master_global), 
  c("country", "region", "population", "elderly_ratio", "life_expectancy", "gdp_per_capita"))
master_global %>%
  filter(!is.na(life_expectancy)) %>%
  arrange(desc(life_expectancy)) %>%
  head(10) %>%
  select(all_of(sample_cols)) %>%
  print()
