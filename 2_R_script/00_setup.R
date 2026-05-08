# ============================================================================
# 00_setup.R
# Global Dog Parks & Urban Livability Analysis - Worldwide
# ============================================================================
# This script sets up the complete R environment for GLOBAL analysis:
# - Analyzes countries with dog park data from Python API
# - Integrates World Bank economic and health indicators
# - Conducts worldwide comparative analysis by region and development level
# Run this script FIRST before executing any other scripts
# ============================================================================

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Global Analysis Setup - Worldwide Dog Parks Study\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# --- 1. Install & Load Required Packages --------------------------------
cat("Loading required packages...\n")

required_packages <- c(
  # Data manipulation
  "tidyverse", "readxl", "jsonlite", "janitor",
  # Spatial analysis
  "sf", "terra", "units", "spdep", "spatialreg", "tmap",
  # Statistical analysis for global comparison
  "FactoMineR", "corrplot", "cluster", "factoextra",
  # Visualization
  "ggplot2", "ggrepel", "viridis", "patchwork", "RColorBrewer",
  # Interactive visualization
  "plotly", "DT", "leaflet", "shiny",
  # World data utilities
  "countrycode", "WDI",  # World Bank data, country codes
  # Utilities
  "here", "scales"
)

# Install missing packages
new_packages <- required_packages[!(required_packages %in% installed.packages()[, "Package"])]
if (length(new_packages) > 0) {
  cat(sprintf("Installing %d new packages...\n", length(new_packages)))
  install.packages(new_packages, dependencies = TRUE, quiet = TRUE)
}

# Load all packages
invisible(lapply(required_packages, library, character.only = TRUE))
cat("✓ All packages loaded successfully!\n\n")

# --- 2. Configure Project Paths ------------------------------------------
cat("Configuring project directory structure for global analysis...\n")

# Project root directory (parent of 2_R_script)
project_root <- dirname(getwd())

# Input data directories
dir_data       <- file.path(project_root, "0_cache")

# Output directories (analysis results) - use 3_output at project root
dir_analysis   <- file.path(project_root, "3_output")
dir_figures    <- file.path(dir_analysis, "figures")
dir_dashboard  <- file.path(dir_analysis, "dashboard")

# Create output directories if they don't exist
for (dir in c(dir_analysis, dir_figures, dir_dashboard)) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
}

cat("✓ Global analysis project paths configured:\n")
cat("  Project root:        ", project_root, "\n")
cat("  Input data:          ", dir_data, "\n")
cat("  Global analysis output: ", dir_analysis, "\n")
cat("  Figures:             ", dir_figures, "\n\n")

# --- 3. Set Spatial Reference Systems -----------------------------------
cat("Configuring spatial reference systems...\n")

# WGS84 (EPSG:4326) - standard for latitude/longitude data worldwide
wgs84  <- 4326

# Web Mercator (EPSG:3857) - for interactive web mapping
web_mercator <- 3857

# Disable S2 spherical geometry to avoid edge crossing errors in buffering
sf_use_s2(FALSE)

cat("✓ CRS configured: WGS84 (EPSG:4326) for analysis\n\n")

# --- 4. Configure Visualization Defaults --------------------------------
cat("Setting up visualization defaults...\n")

# Set tmap mode to static (change to "view" for interactive web maps)
tmap_mode("plot")

# Custom theme for ggplot2 - global style
theme_global <- theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 5)),
    plot.subtitle = element_text(color = "grey40", size = 11, margin = margin(b = 5)),
    plot.caption = element_text(color = "grey60", size = 9, margin = margin(t = 5)),
    legend.position = "right",
    legend.title = element_text(face = "bold", size = 10),
    panel.grid.minor = element_blank(),
    panel.border = element_rect(fill = NA, color = "grey80", size = 0.3)
  )

# Set default ggplot2 theme
theme_set(theme_global)

cat("✓ Visualization defaults configured\n\n")

# --- 5. Global Settings & Constants ----------------------------------------
cat("Setting global analysis parameters...\n")

# Analysis configuration
ANALYSIS_YEAR <- 2023
N_COUNTRIES <- 195
WORLD_REGIONS <- c("Asia", "Europe", "Africa", "Americas", "Oceania")

# Global ranking thresholds (0-100 scale)
RANK_TOP_TIER <- 0.75      # Top 25% of countries
RANK_GOOD <- 0.60          # Top 40% of countries
RANK_AVERAGE <- 0.45       # Top 55% of countries
RANK_POOR <- 0.30          # Below average performers

# Color palettes for global analysis
palette_regions <- c(
  "Asia" = "#E74C3C",
  "Europe" = "#3498DB",
  "Africa" = "#F39C12",
  "Americas" = "#2ECC71",
  "Oceania" = "#9B59B6"
)

cat("✓ Global parameters configured\n\n")

# --- 6. Functions - Data Loading & Preprocessing -------------------------
cat("Defining helper functions for global analysis...\n")

# Function: Load CSV data (e.g., Python-collected dog park data)
load_analysis_data <- function(filename, dir = NULL) {
  # Try multiple locations for data files
  if (is.null(dir)) {
    # First try project 3_output (newer data location)
    filepath <- file.path(project_root, "3_output", filename)
    if (!file.exists(filepath)) {
      # Then try 0_cache (backup location)
      filepath <- file.path(project_root, "0_cache", filename)
    }
    if (!file.exists(filepath)) {
      # Try current dir_data
      filepath <- file.path(dir_data, filename)
    }
  } else {
    filepath <- file.path(dir, filename)
  }

  if (!file.exists(filepath)) {
    warning(sprintf("File not found: %s", filepath))
    return(NULL)
  }
  read_csv(filepath, show_col_types = FALSE) %>%
    janitor::clean_names()
}

# Function: Standardize variable to 0-100 scale
standardize_to_100 <- function(x) {
  (x - min(x, na.rm = TRUE)) / (max(x, na.rm = TRUE) - min(x, na.rm = TRUE)) * 100
}

# Function: Assign country development tier
categorize_country <- function(score) {
  case_when(
    score >= 75 ~ "Top Tier",
    score >= 60 ~ "Advanced",
    score >= 45 ~ "Developing",
    score >= 30 ~ "Emerging",
    TRUE ~ "Low Tier"
  )
}

# Function: Get region from country code
get_region <- function(country_code) {
  countrycode(country_code, origin = "iso2c", destination = "region")
}

# Function: Get country name from code
get_country_name <- function(country_code) {
  countrycode(country_code, origin = "iso2c", destination = "country.name")
}

# Function: Calculate Gini coefficient (income/distribution inequality)
# Gini = 0 (perfect equality) to 1 (perfect inequality)
gini <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) return(NA)

  x <- sort(x)
  n <- length(x)

  # Gini formula: G = (2 * sum(i * x_i)) / (n * sum(x)) - (n + 1) / n
  gini_coef <- (2 * sum(seq_along(x) * x)) / (n * sum(x)) - (n + 1) / n

  # Ensure result is between 0 and 1
  return(max(0, min(1, gini_coef)))
}

cat("✓ Helper functions defined\n\n")

# --- 7. Session Summary --------------------------------------------------
cat("═══════════════════════════════════════════════════════════════\n")
cat("Setup Complete - Ready for Global Analysis!\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Session Information:\n")
cat("  R version:       ", R.version$major, ".", R.version$minor, "\n", sep = "")
cat("  Packages:        ", length(required_packages), " loaded\n")
cat("  Analysis type:   GLOBAL (195+ countries)\n")
cat("  Analysis year:   ", ANALYSIS_YEAR, "\n")
cat("  World regions:   ", paste(WORLD_REGIONS, collapse = ", "), "\n")
cat("  Output folder:   ", dir_analysis, "\n")
cat("\nNext step: Run 01_global_data_integration.R\n")
cat("═══════════════════════════════════════════════════════════════\n\n")
