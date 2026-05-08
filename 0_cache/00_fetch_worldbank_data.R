# Global Green Space and Health Dashboard - Data Fetching Script
# Global Dashboard - Data Fetching Script
# This script uses World Bank public API to fetch global indicators

# ============================================================================
# SETUP
# ============================================================================

cat("\n=== Global Data Fetching from World Bank ===\n")

# Check and install necessary packages
required_packages <- c("wbstats", "tidyverse", "sf", "jsonlite")

for (pkg in required_packages) {
  if (!require(pkg, character.only = TRUE)) {
    cat(sprintf("Installing %s...\n", pkg))
    install.packages(pkg, quiet = TRUE)
    library(pkg, character.only = TRUE)
  }
}

cat("✓ All packages loaded\n\n")

# Create data directory
dir.create("data/fetched", recursive = TRUE, showWarnings = FALSE)

# ============================================================================
# STEP 1: Get all country lists and geographic information
# ============================================================================

cat("--- STEP 1: Fetching Country List and Centroids ---\n")

# Get World Bank country list
tryCatch({
  all_countries <- wb_countries()
  
  # Handle different versions of wbstats returning different column names
  # Select existing columns
  available_cols <- colnames(all_countries)
  cols_to_select <- c("iso3c", "iso2c", "country", "region", "longitude", "latitude")
  cols_to_select <- cols_to_select[cols_to_select %in% available_cols]
  
  all_countries <- all_countries %>%
    select(all_of(cols_to_select)) %>%
    filter(!is.na(longitude), !is.na(latitude))
  
  cat(sprintf("✓ Retrieved %d countries with geographic data\n", nrow(all_countries)))
  
  # Save as reference
  write_csv(all_countries, "data/fetched/country_reference.csv")
  
}, error = function(e) {
  cat("⚠️  Error fetching country list:", conditionMessage(e), "\n")
  cat("   Creating fallback country list...\n")
  
  # Fallback: Use static country list
  all_countries <<- tibble(
    iso3c = c("USA", "CHN", "IND", "JPN", "DEU", "GBR", "FRA", "ITA", "CAN", "KOR",
              "BRA", "MEX", "IDN", "RUS", "AUS", "ESP", "NLD", "SAU", "CHE", "SWE",
              "POL", "BEL", "ARG", "NOR", "AUT", "NZL", "DNK", "ISR", "SGP", "MYS"),
    country = c("United States", "China", "India", "Japan", "Germany", "United Kingdom", 
                "France", "Italy", "Canada", "Korea", "Brazil", "Mexico", "Indonesia", 
                "Russia", "Australia", "Spain", "Netherlands", "Saudi Arabia", 
                "Switzerland", "Sweden", "Poland", "Belgium", "Argentina", "Norway", 
                "Austria", "New Zealand", "Denmark", "Israel", "Singapore", "Malaysia"),
    longitude = c(-95.7, 104.2, 78.96, 138.25, 10.45, -3.44, 2.21, 12.57, -95.71, 127.77,
                  -51.92, -102.55, 113.92, 105.32, 133.78, -3.74, 5.29, 45.08, 8.23, 18.64,
                  19.15, 4.47, -63.62, 8.47, 14.55, 174.88, 9.50, 35.23, 103.81, 101.69),
    latitude = c(37.09, 35.86, 20.59, 36.20, 51.17, 55.38, 46.23, 41.87, 56.13, 37.27,
                 -14.24, 23.63, -0.79, 61.52, -25.27, 40.46, 52.13, 23.89, 46.82, 60.13,
                 51.92, 50.50, -38.42, 60.47, 47.52, -40.90, 56.27, 31.95, 1.35, 4.21)
  )
  
  cat("✓ Using fallback country list with", nrow(all_countries), "countries\n")
})

# ============================================================================
# STEP 2: Population Data (World Bank - SP.POP.TOTL)
# ============================================================================

cat("\n--- STEP 2: Fetching Population Data ---\n")

tryCatch({
  population_data <- wb_data(
    indicator = "SP.POP.TOTL",
    start_date = 2020,
    end_date = 2023,
    return_wide = FALSE,
    mrnev = 1  # Latest non-empty value
  ) %>%
    filter(!is.na(value)) %>%
    select(iso3c = country, date, population = value) %>%
    mutate(year = as.numeric(date))
  
  cat(sprintf("✓ Retrieved population data for %d countries\n", 
              n_distinct(population_data$iso3c)))
  
  write_csv(population_data, "data/fetched/population_data.csv")
  
}, error = function(e) {
  cat("⚠️  Error fetching population data:", conditionMessage(e), "\n")
  cat("   Creating synthetic population data for demo...\n")
  
  # Create sample data for demo
  population_data <<- expand_grid(
    iso3c = all_countries$iso3c,
    year = 2023
  ) %>%
    mutate(
      population = runif(n(), 1e6, 1.4e9),  # 1 million to 1.4 billion
      date = as.character(year)
    ) %>%
    select(iso3c, date, population, year)
  
  cat(sprintf("✓ Using synthetic data for %d countries\n", 
              n_distinct(population_data$iso3c)))
})

# ============================================================================
# STEP 3: Health Indicators - Key Indicator Set
# ============================================================================

cat("\n--- STEP 3: Fetching Health Indicators ---\n")

cat("\n--- STEP 3: Fetching Health Indicators ---\n")

# Define health indicators to fetch
health_indicators <- list(
  life_expectancy = "SP.DYN.LE00.IN",           # Life expectancy at birth
  mortality_under5 = "SP.DYN.CDRT.IN",          # Under-five child mortality rate
  health_expenditure_pct_gdp = "SH.XPD.CHEX.GD.ZS" # Health expenditure as %GDP
)

health_data <- NULL

for (i in seq_along(health_indicators)) {
  indicator_name <- names(health_indicators)[i]
  indicator_code <- health_indicators[[i]]
  
  cat(sprintf("  Fetching %s (%s)...", indicator_name, indicator_code))
  
  tryCatch({
    temp_data <- wb_data(
      indicator = indicator_code,
      start_date = 2018,
      end_date = 2023,
      return_wide = FALSE,
      mrnev = 1
    ) %>%
      filter(!is.na(value)) %>%
      select(iso3c = country, date, !!indicator_name := value)
    
    if (is.null(health_data)) {
      health_data <<- temp_data
    } else {
      health_data <<- health_data %>%
        left_join(temp_data, by = c("iso3c", "date"))
    }
    
    cat(" ✓\n")
    Sys.sleep(0.3)  # API throttling
    
  }, error = function(e) {
    cat(sprintf(" (failed)\n"))
  })
}

# If fetch failed, create sample data
if (is.null(health_data) || nrow(health_data) == 0) {
  cat("⚠️  Creating synthetic health data for demo...\n")
  health_data <- expand_grid(
    iso3c = all_countries$iso3c,
    date = "2023"
  ) %>%
    mutate(
      life_expectancy = runif(n(), 50, 85),
      mortality_under5 = runif(n(), 5, 100),
      health_expenditure_pct_gdp = runif(n(), 1, 10)
    )
}

cat(sprintf("✓ Health data ready for %d countries\n", 
            n_distinct(health_data$iso3c)))

write_csv(health_data, "data/fetched/health_indicators.csv")

# ============================================================================
# STEP 4: Economic Indicators (GDP, Development Level, etc.)
# ============================================================================

cat("\n--- STEP 4: Fetching Economic Indicators ---\n")

economic_indicators <- list(
  gdp_per_capita = "NY.GDP.PCAP.CD",            # GDP per capita (current USD)
  gni_per_capita = "NY.GNP.PCAP.CD",            # GNI per capita (current USD)
  urbanization_rate = "SP.URB.TOTL.IN.ZS"       # Urbanization rate
)

economic_data <- NULL

for (i in seq_along(economic_indicators)) {
  indicator_name <- names(economic_indicators)[i]
  indicator_code <- economic_indicators[[i]]
  
  cat(sprintf("  Fetching %s...", indicator_name))
  
  tryCatch({
    temp_data <- wb_data(
      indicator = indicator_code,
      start_date = 2018,
      end_date = 2023,
      return_wide = FALSE,
      mrnev = 1
    ) %>%
      filter(!is.na(value)) %>%
      select(iso3c = country, date, !!indicator_name := value)
    
    if (is.null(economic_data)) {
      economic_data <<- temp_data
    } else {
      economic_data <<- economic_data %>%
        left_join(temp_data, by = c("iso3c", "date"))
    }
    
    cat(" ✓\n")
    Sys.sleep(0.3)
    
  }, error = function(e) {
    cat(" (failed)\n")
  })
}

# If fetch failed, create sample data
if (is.null(economic_data) || nrow(economic_data) == 0) {
  cat("⚠️  Creating synthetic economic data for demo...\n")
  economic_data <- expand_grid(
    iso3c = all_countries$iso3c,
    date = "2023"
  ) %>%
    mutate(
      gdp_per_capita = runif(n(), 500, 70000),
      gni_per_capita = runif(n(), 500, 70000),
      urbanization_rate = runif(n(), 10, 100)
    )
}

cat(sprintf("✓ Economic data ready for %d countries\n", 
            n_distinct(economic_data$iso3c)))

write_csv(economic_data, "data/fetched/economic_indicators.csv")

# ============================================================================
# STEP 5: Environmental and Urban Indicators
# ============================================================================

cat("\n--- STEP 5: Fetching Environmental Indicators ---\n")

environmental_indicators <- list(
  forest_area_pct = "AG.LND.FRST.ZS",           # Forest area as % of land
  pm25_concentration = "EN.ATM.PM25.MC.M3",     # PM2.5 concentration
  access_to_electricity = "EG.ELC.ACCS.ZS",     # Access to electricity
  renewable_energy_pct = "EG.FEC.RNEW.ZS"       # Renewable energy share
)

environmental_data <- NULL

for (i in seq_along(environmental_indicators)) {
  indicator_name <- names(environmental_indicators)[i]
  indicator_code <- environmental_indicators[[i]]
  
  cat(sprintf("  Fetching %s...", indicator_name))
  
  tryCatch({
    temp_data <- wb_data(
      indicator = indicator_code,
      start_date = 2018,
      end_date = 2023,
      return_wide = FALSE,
      mrnev = 1
    ) %>%
      filter(!is.na(value)) %>%
      select(iso3c = country, date, !!indicator_name := value)
    
    if (is.null(environmental_data)) {
      environmental_data <<- temp_data
    } else {
      environmental_data <<- environmental_data %>%
        left_join(temp_data, by = c("iso3c", "date"))
    }
    
    cat(" ✓\n")
    Sys.sleep(0.3)
    
  }, error = function(e) {
    cat(" (failed)\n")
  })
}

# If fetch failed, create sample data
if (is.null(environmental_data) || nrow(environmental_data) == 0) {
  cat("⚠️  Creating synthetic environmental data for demo...\n")
  environmental_data <- expand_grid(
    iso3c = all_countries$iso3c,
    date = "2023"
  ) %>%
    mutate(
      forest_area_pct = runif(n(), 0, 80),
      pm25_concentration = runif(n(), 5, 150),
      access_to_electricity = runif(n(), 50, 100),
      renewable_energy_pct = runif(n(), 0, 100)
    )
}

cat(sprintf("✓ Environmental data ready for %d countries\n", 
            n_distinct(environmental_data$iso3c)))

write_csv(environmental_data, "data/fetched/environmental_indicators.csv")

# ============================================================================
# STEP 6: Merge all data
# ============================================================================

cat("\n--- STEP 6: Merging All Data ---\n")

# Ensure all data frames have iso3c and date columns
if (!("date" %in% colnames(population_data))) {
  population_data <- population_data %>% mutate(date = "2023")
}
if (!("date" %in% colnames(health_data))) {
  health_data <- health_data %>% mutate(date = "2023")
}
if (!("date" %in% colnames(economic_data))) {
  economic_data <- economic_data %>% mutate(date = "2023")
}
if (!("date" %in% colnames(environmental_data))) {
  environmental_data <- environmental_data %>% mutate(date = "2023")
}

# Merge all indicators
global_indicators <- all_countries %>%
  left_join(population_data %>% select(-any_of("year")), 
            by = "iso3c") %>%
  left_join(health_data, by = c("iso3c", "date")) %>%
  left_join(economic_data, by = c("iso3c", "date")) %>%
  left_join(environmental_data, by = c("iso3c", "date")) %>%
  rename(year = date) %>%
  filter(!is.na(population))  # At least have population data

cat(sprintf("✓ Merged dataset: %d countries × %d variables\n",  
            n_distinct(global_indicators$country),
            ncol(global_indicators)))


# ============================================================================
# STEP 7: Data Cleaning & Standardization
# ============================================================================

cat("\n--- STEP 7: Data Cleaning & Standardization ---\n")

global_data <- global_indicators %>%
  # Remove infinite values
  mutate(across(where(is.numeric), 
                ~replace(., is.infinite(.), NA))) %>%
  
  # Calculate per capita indicators
  mutate(
    health_expenditure_per_capita = 
      health_expenditure_pc * population / 1e9  # Simplified calculation
  ) %>%
  
  # Group by country and year, take latest data
  group_by(iso3c) %>%
  arrange(desc(year)) %>%
  slice(1) %>%
  ungroup() %>%
  
  # Data availability check
  mutate(
    data_completeness = rowSums(!is.na(select(., where(is.numeric)))) /
      sum(sapply(select(., where(is.numeric)), 
                 function(x) !all(is.na(x))))
  )

cat(sprintf("✓ Data cleaned: %d countries with usable data\n", nrow(global_data)))

# ============================================================================
# HELPER: Normalization function (define before use)
# ============================================================================

scale_to_100 <- function(x, min_val = NULL, max_val = NULL) {
  # If no min/max provided, use data min/max
  if (is.null(min_val)) min_val <- min(x, na.rm = TRUE)
  if (is.null(max_val)) max_val <- max(x, na.rm = TRUE)
  
  if (min_val == max_val) return(rep(50, length(x)))  # Avoid division by 0
  return(pmax(0, pmin(100, ((x - min_val) / (max_val - min_val)) * 100)))
}

# ============================================================================
# STEP 8: Synthetic Indicator Calculation
# ============================================================================

cat("\n--- STEP 8: Calculating Synthetic Indicators ---\n")

global_data <- global_data %>%
  mutate(
    # Quality of life index (0-100 scale)
    health_index = scale_to_100(life_expectancy, 50, 85),
    
    # Development level index
    development_index = scale_to_100(gdp_per_capita, 0, 60000),
    
    # Environmental index (forest area as proxy)
    environment_index = scale_to_100(forest_area_pct, 0, 100),
    
    # Urbanization level
    urbanization_index = scale_to_100(urbanization_rate, 0, 100),
    
    # Fill missing values with simple average
    health_index = coalesce(health_index, mean(health_index, na.rm = TRUE)),
    development_index = coalesce(development_index, mean(development_index, na.rm = TRUE)),
    forest_area_pct = coalesce(forest_area_pct, mean(forest_area_pct, na.rm = TRUE)),
    pm25_concentration = coalesce(pm25_concentration, mean(pm25_concentration, na.rm = TRUE)),
    renewable_energy_pct = coalesce(renewable_energy_pct, mean(renewable_energy_pct, na.rm = TRUE))
  )

cat("✓ Synthetic indicators calculated\n")

# ============================================================================
# STEP 9: Green Space Proxy Index
# ============================================================================

cat("\n--- STEP 9: Creating Green Space Proxy Index ---\n")

# Since OSM data needs separate processing, create proxy index as follows:
# = Forest area + Urbanization rate + Environmental investment willingness

global_data <- global_data %>%
  mutate(
    # Ensure all necessary columns exist
    forest_area_pct = coalesce(forest_area_pct, 30),  # Default value
    urbanization_rate = coalesce(urbanization_rate, 50),
    renewable_energy_pct = coalesce(renewable_energy_pct, 15),
    pm25_concentration = coalesce(pm25_concentration, 50),
    
    # Green space proxy index
    green_space_proxy = (
      forest_area_pct * 0.4 +          # Forest coverage
      (100 - urbanization_rate) * 0.2 +  # Non-urbanized areas
      renewable_energy_pct * 0.2 +       # Renewable energy investment
      pmax(0, (100 - pm25_concentration)) * 0.2  # Air quality (inverse indicator)
    ),
    
    green_space_proxy = pmax(0, pmin(100, green_space_proxy))
  )

cat("✓ Green space proxy index created\n")

cat("\n--- STEP 10: Computing Final Scores ---\n")

global_data <- global_data %>%
  mutate(
    # Ensure all health indicators exist
    life_expectancy = coalesce(life_expectancy, 72),
    health_expenditure_pct_gdp = coalesce(health_expenditure_pct_gdp, 5),
    
    # Healthcare access proxy (using health expenditure and life expectancy)
    healthcare_access = (
      (life_expectancy / 85) * 0.7 +  # Health outcomes (70%)
      (health_expenditure_pct_gdp / 10) * 0.3   # Health investment (30%)
    ) * 100,
    healthcare_access = pmax(0, pmin(100, healthcare_access)),
    
    # Ensure core indicators exist
    green_space_proxy = coalesce(green_space_proxy, 50),
    health_index = coalesce(health_index, 50),
    
    # Final composite score
    overall_score = (
      green_space_proxy * 0.35 +
      health_index * 0.35 +
      healthcare_access * 0.30
    ),
    
    # Ranking
    rank_overall = rank(-overall_score, na.last = "keep", ties.method = "min"),
    rank_health = rank(-health_index, na.last = "keep", ties.method = "min"),
    rank_green = rank(-green_space_proxy, na.last = "keep", ties.method = "min"),
    
    # Classification
    category = case_when(
      overall_score >= 75 ~ "Excellent",
      overall_score >= 60 ~ "Good",
      overall_score >= 45 ~ "Fair",
      overall_score >= 30 ~ "Poor",
      TRUE ~ "Critical"
    ),
    
    # Compare to global average
    global_mean_health = mean(health_index, na.rm = TRUE),
    global_mean_green = mean(green_space_proxy, na.rm = TRUE),
    vs_global_health = health_index - global_mean_health,
    vs_global_green = green_space_proxy - global_mean_green
  )

cat("✓ Final scores computed\n")

# ============================================================================
# STEP 11: Export to GeoJSON (for frontend use)
# ============================================================================

cat("\n--- STEP 11: Exporting to GeoJSON ---\n")

# Select needed columns
export_cols <- c(
  "country", "iso3c", "population", "year",
  "life_expectancy", "gdp_per_capita", "forest_area_pct",
  "green_space_proxy", "health_index", "healthcare_access",
  "overall_score", "rank_overall",
  "vs_global_green", "vs_global_health",
  "category", "longitude", "latitude"
)

geojson_data <- global_data %>%
  select(any_of(export_cols)) %>%
  filter(
    !is.na(longitude) & !is.na(latitude) & 
    !is.infinite(longitude) & !is.infinite(latitude) &
    !is.na(overall_score)
  ) %>%
  # 修复坐标范围
  filter(
    longitude >= -180 & longitude <= 180,
    latitude >= -90 & latitude <= 90
  )

# Create output directory
dir.create("frontend/data", recursive = TRUE, showWarnings = FALSE)

if (nrow(geojson_data) > 0) {
  # Convert to SF object (points)
  geojson_sf <- geojson_data %>%
    st_as_sf(coords = c("longitude", "latitude"), crs = 4326)
  
  # Export GeoJSON
  st_write(
    geojson_sf,
    "frontend/data/world_data.geojson",
    driver = "GeoJSON",
    delete_dsn = TRUE,
    quiet = TRUE
  )
  
  cat(sprintf("✓ Exported %d countries to frontend/data/world_data.geojson\n", 
              nrow(geojson_data)))
} else {
  cat("⚠️  No valid coordinate data to export\n")
}

# ============================================================================
# STEP 12: Summary Statistics
# ============================================================================

cat("\n--- STEP 12: Summary Statistics ---\n")

tryCatch({
  summary_stats <- global_data %>%
    summarise(
      countries_total = n(),
      avg_overall_score = mean(overall_score, na.rm = TRUE),
      avg_green_proxy = mean(green_space_proxy, na.rm = TRUE),
      avg_health = mean(health_index, na.rm = TRUE),
      avg_healthcare = mean(healthcare_access, na.rm = TRUE),
      avg_gdp_pc = mean(gdp_per_capita, na.rm = TRUE),
      avg_life_exp = mean(life_expectancy, na.rm = TRUE)
    )
  
  cat("\n📊 GLOBAL SUMMARY\n")
  cat(strrep("─", 50) %+% "\n")
  cat(sprintf("Countries analyzed: %d\n", summary_stats$countries_total))
  cat(sprintf("Avg Overall Score: %.1f/100\n", summary_stats$avg_overall_score))
  cat(sprintf("Avg Green Space (proxy): %.1f/100\n", summary_stats$avg_green_proxy))
  cat(sprintf("Avg Health Index: %.1f/100\n", summary_stats$avg_health))
  cat(sprintf("Avg Healthcare Access: %.1f/100\n", summary_stats$avg_healthcare))
  cat(sprintf("Avg GDP per Capita: $%.0f\n", summary_stats$avg_gdp_pc))
  cat(sprintf("Avg Life Expectancy: %.1f years\n", summary_stats$avg_life_exp))
  cat(strrep("─", 50) %+% "\n")
  
}, error = function(e) {
  cat("⚠️  Could not calculate summary statistics\n")
})

# ============================================================================
# Export CSV for reference and backup
# ============================================================================

tryCatch({
  write_csv(global_data, "data/fetched/global_integrated_data.csv")
  cat("✓ CSV data exported to data/fetched/global_integrated_data.csv\n")
}, error = function(e) {
  cat("⚠️  Could not export CSV data\n")
})

cat("\n✅ DATA PROCESSING COMPLETE!\n")
cat(strrep("═", 50) %+% "\n\n")
cat("Output files:\n")
cat("  ✓ frontend/data/world_data.geojson (for dashboard)\n")
cat("  ✓ data/fetched/global_integrated_data.csv (for analysis)\n\n")
cat("Next step: Open frontend/index.html in your browser!\n\n")
