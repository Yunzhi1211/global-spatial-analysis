# ============================================================================
# 00_setup.R
# Global Dog Parks Analysis - Setup & Configuration
# ============================================================================
# This script installs and loads all required packages, and sets up paths.
# Run this script FIRST before any other scripts.
# ============================================================================

# --- 1. Install required packages (only need to run once) -------------------
required_packages <- c(
  # Spatial data handling
  "sf",           # Simple Features - read/write/manipulate spatial data
  "terra",        # Raster data handling
  "units",        # Unit conversions for spatial calculations
  

  # Spatial analysis
  "spdep",        # Spatial dependence: Moran's I, LISA, spatial weights
  "spatialreg",   # Spatial regression models (Lag, Error)
  "spgwr",        # Geographically Weighted Regression
  "spatstat",     # Point pattern analysis, KDE
  
  # Data manipulation
  "tidyverse",    # dplyr, ggplot2, tidyr, readr, etc.
  "readxl",       # Read Excel files
  "janitor",      # Clean column names
  "jsonlite",     # Read JSON files
  
  # Visualization & Mapping
  "tmap",         # Thematic maps (static & interactive)
  "ggplot2",      # Grammar of graphics plotting
  "viridis",      # Color palettes
  "patchwork",    # Combine multiple ggplots
  "RColorBrewer", # Color palettes for maps
  "classInt",     # Classification intervals for choropleth
  
  # Tables & reporting
  "knitr",        # Tables
  "kableExtra",   # Enhanced tables
  "stargazer"     # Regression tables
)

# Install missing packages
new_packages <- required_packages[!(required_packages %in% installed.packages()[, "Package"])]
if (length(new_packages) > 0) {
  install.packages(new_packages, dependencies = TRUE)
}

# Load all packages
invisible(lapply(required_packages, library, character.only = TRUE))

cat("All packages loaded successfully!\n")

# --- 2. Set project paths ---------------------------------------------------
# Automatically detect project root (works when sourced from project directory)
project_root <- getwd()

# Data directories
dir_data      <- file.path(project_root, "data")
dir_census    <- file.path(dir_data, "census")
dir_health    <- file.path(dir_data, "health")
dir_spatial   <- file.path(dir_data, "spatial")
dir_pet       <- file.path(dir_data, "pet_gardens")

# Output directories (create if not exist)
dir_output    <- file.path(project_root, "output")
dir_figures   <- file.path(project_root, "figures")
dir.create(dir_output, showWarnings = FALSE, recursive = TRUE)
dir.create(dir_figures, showWarnings = FALSE, recursive = TRUE)

# Path to downloaded Geofabrik OSM shapefile
# NOTE: Update this path if you saved the shapefile elsewhere
osm_shp_dir <- "C:/Users/lenovo/Downloads/hong-kong-260416-free.shp"

cat("Project paths configured.\n")
cat("  Project root:", project_root, "\n")
cat("  OSM SHP dir: ", osm_shp_dir, "\n")

# --- 3. Set CRS constants ---------------------------------------------------
# Hong Kong 1980 Grid (EPSG:2326) - for distance calculations in meters
hk_crs <- 2326
# WGS84 (EPSG:4326) - for lat/lon data
wgs84  <- 4326

# Disable S2 spherical geometry to avoid edge crossing errors
sf_use_s2(FALSE)

# --- 4. Set tmap mode -------------------------------------------------------
tmap_mode("plot")  # Use "view" for interactive maps

# --- 5. Custom theme for ggplot2 ---------------------------------------------
theme_hk <- theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "grey40"),
    legend.position = "right",
    panel.grid.minor = element_blank()
  )

cat("\n=== Setup complete! ===\n")
