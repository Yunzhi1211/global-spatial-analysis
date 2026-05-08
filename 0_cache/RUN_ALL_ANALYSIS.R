# ============================================================================
# RUN_ALL_ANALYSIS.R
# Master Control Script - Execute Complete Analysis Pipeline
# ============================================================================
# This script runs all 7 analysis modules in sequence
# Simply source this file: source("RUN_ALL_ANALYSIS.R")
# ============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   Urban Green Space Analysis Pipeline - Complete Execution    ║\n")
cat("║   Hong Kong Urban Green Space & Pet Parks Analysis            ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Project metadata
PROJECT_NAME <- "Hong Kong Urban Green Space & Pet Parks"
ANALYSIS_YEAR <- 2023
START_TIME <- Sys.time()

cat("PROJECT:", PROJECT_NAME, "\n")
cat("ANALYSIS YEAR:", ANALYSIS_YEAR, "\n")
cat("START TIME:", format(START_TIME, "%Y-%m-%d %H:%M:%S"), "\n\n")

# Define analysis modules
modules <- list(
  list(script = "00_setup.R",
       description = "Environment Setup & Configuration"),
  list(script = "01_data_integration.R",
       description = "Data Integration (Python + Local Data)"),
  list(script = "02_exploratory_analysis.R",
       description = "Exploratory Data Analysis"),
  list(script = "03_green_space_analysis.R",
       description = "Green Space Analysis & Equity"),
  list(script = "04_population_health_analysis.R",
       description = "Population Health Analysis"),
  list(script = "05_global_ranking_analysis.R",
       description = "Global Ranking & Comparative Analysis"),
  list(script = "06_spatial_analysis.R",
       description = "Spatial Autocorrelation & Hot Spots"),
  list(script = "07_interactive_dashboard.R",
       description = "Interactive Dashboard Generation")
)

# ============================================================================
# PART 1: Check Prerequisites
# ============================================================================
cat("═══════════════════════════════════════════════════════════════════\n")
cat("STEP 0: Checking Prerequisites\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

# Check required data files
required_files <- c(
  "0_cache/pet_parks_by_country_updated.csv",
  "0_cache/hk_18_districts.geojson",
  "0_cache/green_spaces_osm.geojson",
  "0_cache/master_district_data.csv"
)

cat("Checking for required data files...\n")
missing_files <- c()

for (file in required_files) {
  if (file.exists(file)) {
    cat("  ✓", file, "\n")
  } else {
    cat("  ✗", file, "NOT FOUND\n")
    missing_files <- c(missing_files, file)
  }
}

if (length(missing_files) > 0) {
  cat("\n⚠️  WARNING: The following files are missing:\n")
  for (file in missing_files) {
    cat("  -", file, "\n")
  }
  cat("\nThe analysis may not complete successfully. Ensure all data files are present.\n\n")
}

cat("✓ Prerequisites check complete\n\n")

# ============================================================================
# PART 2: Execute Each Module
# ============================================================================
cat("═══════════════════════════════════════════════════════════════════\n")
cat("EXECUTING ANALYSIS PIPELINE\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

execution_log <- data.frame(
  module_num = integer(0),
  script_name = character(0),
  description = character(0),
  start_time = as.POSIXct(character(0)),
  end_time = as.POSIXct(character(0)),
  duration_seconds = numeric(0),
  status = character(0),
  error_message = character(0)
)

for (i in seq_along(modules)) {
  module <- modules[[i]]
  script <- module$script
  desc <- module$description
  
  # Progress indicator
  cat(sprintf("\n[%d/%d] %s\n", i, length(modules), desc))
  cat("───────────────────────────────────────────────────\n")
  
  module_start <- Sys.time()
  
  # Try to execute the module
  tryCatch({
    # Source the script
    source(script, local = FALSE)
    
    module_end <- Sys.time()
    duration <- as.numeric(difftime(module_end, module_start, units = "secs"))
    
    # Log success
    execution_log <- rbind(execution_log, data.frame(
      module_num = i,
      script_name = script,
      description = desc,
      start_time = module_start,
      end_time = module_end,
      duration_seconds = duration,
      status = "SUCCESS",
      error_message = ""
    ))
    
    cat(sprintf("✓ COMPLETED in %.1f seconds\n", duration))
    
  }, error = function(e) {
    module_end <- Sys.time()
    duration <- as.numeric(difftime(module_end, module_start, units = "secs"))
    
    # Log error
    execution_log <<- rbind(execution_log, data.frame(
      module_num = i,
      script_name = script,
      description = desc,
      start_time = module_start,
      end_time = module_end,
      duration_seconds = duration,
      status = "ERROR",
      error_message = as.character(e)
    ))
    
    cat(sprintf("✗ ERROR: %s\n", e$message))
    cat("  Continuing with next module...\n")
  })
}

# ============================================================================
# PART 3: Generate Execution Report
# ============================================================================
cat("\n\n═══════════════════════════════════════════════════════════════════\n")
cat("EXECUTION SUMMARY\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

END_TIME <- Sys.time()
TOTAL_DURATION <- as.numeric(difftime(END_TIME, START_TIME, units = "mins"))

# Count results
successful <- sum(execution_log$status == "SUCCESS")
failed <- sum(execution_log$status == "ERROR")

cat(sprintf("Total Modules: %d\n", length(modules)))
cat(sprintf("Successful: %d ✓\n", successful))
cat(sprintf("Failed: %d ✗\n", failed))
cat(sprintf("Success Rate: %.1f%%\n\n", (successful / length(modules)) * 100))

cat(sprintf("Total Execution Time: %.1f minutes\n", TOTAL_DURATION))
cat(sprintf("Average Time per Module: %.1f seconds\n\n", 
            mean(execution_log$duration_seconds)))

# Print module timings
cat("Module Execution Times:\n")
cat("───────────────────────────────────────────────────\n")

for (i in 1:nrow(execution_log)) {
  row <- execution_log[i, ]
  status_icon <- ifelse(row$status == "SUCCESS", "✓", "✗")
  cat(sprintf("%s [%d] %s: %.1f sec\n",
              status_icon, row$module_num, 
              row$script_name, row$duration_seconds))
}

# List generated outputs
cat("\n\n═══════════════════════════════════════════════════════════════════\n")
cat("GENERATED OUTPUTS\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

if (dir.exists("analysis_results")) {
  output_files <- list.files("analysis_results", recursive = TRUE)
  
  # Categorize files
  csv_files <- output_files[grep("\\.csv$", output_files)]
  rdata_files <- output_files[grep("\\.RData$", output_files)]
  html_files <- output_files[grep("\\.html$", output_files)]
  png_files <- output_files[grep("\\.png$", output_files)]
  txt_files <- output_files[grep("\\.txt$", output_files)]
  
  cat("CSV Files:", length(csv_files), "\n")
  for (f in head(csv_files, 3)) {
    cat("  •", f, "\n")
  }
  if (length(csv_files) > 3) cat("  ... and", length(csv_files) - 3, "more\n")
  
  cat("\nRData Files:", length(rdata_files), "\n")
  for (f in rdata_files) {
    cat("  •", f, "\n")
  }
  
  cat("\nHTML Dashboard:", length(html_files), "\n")
  for (f in html_files) {
    cat("  ★", f, "(INTERACTIVE DASHBOARD)\n")
  }
  
  cat("\nVisualization Figures:", length(png_files), "\n")
  cat("  • PNG files:", length(png_files), "high-resolution charts & maps\n")
  
  cat("\nDocumentation:", length(txt_files), "\n")
  for (f in txt_files) {
    cat("  •", f, "\n")
  }
  
  cat("\n\nTotal Output Files:", length(output_files), "\n")
  cat("Total Output Size:", 
      format(sum(file.size("analysis_results")), units = "Mb"),
      "\n\n")
}

# ============================================================================
# PART 4: Final Instructions
# ============================================================================
cat("═══════════════════════════════════════════════════════════════════\n")
cat("NEXT STEPS - HOW TO VIEW YOUR RESULTS\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

if (file.exists("analysis_results/07_interactive_district_explorer.html")) {
  cat("★ PRIMARY DELIVERABLE:\n")
  cat("  Open this file in your web browser:\n")
  cat("  >>> analysis_results/07_interactive_district_explorer.html <<<\n\n")
  cat("  This interactive dashboard allows you to:\n")
  cat("  • Select and explore each district\n")
  cat("  • View global rankings and comparative metrics\n")
  cat("  • Identify strengths and weaknesses\n")
  cat("  • Compare with peer districts\n")
  cat("  • Get evidence-based improvement recommendations\n\n")
}

cat("Additional Output Files:\n")
cat("  📊 CSV Files: Statistical results in spreadsheet format\n")
cat("  📈 PNG Figures: Publication-quality maps & charts\n")
cat("  📄 RData Files: R data objects for further analysis\n")
cat("  📋 TXT Reports: Summary reports for each analysis module\n\n")

cat("Recommended Viewing Order:\n")
cat("  1. 07_interactive_district_explorer.html (Main Dashboard)\n")
cat("  2. analysis_results/*.csv (Data tables)\n")
cat("  3. analysis_results/figures/*.png (Visualizations)\n")
cat("  4. analysis_results/*_summary.txt (Summary reports)\n\n")

# ============================================================================
# PART 5: Save Execution Log
# ============================================================================
execution_log$start_time <- format(execution_log$start_time, "%H:%M:%S")
execution_log$end_time <- format(execution_log$end_time, "%H:%M:%S")

write.csv(execution_log, 
         "analysis_results/EXECUTION_LOG.csv",
         row.names = FALSE)

cat("✓ Execution log saved: analysis_results/EXECUTION_LOG.csv\n\n")

# ============================================================================
# Final Summary
# ============================================================================
cat("═══════════════════════════════════════════════════════════════════\n")
cat("ANALYSIS PIPELINE EXECUTION COMPLETE\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

if (failed == 0) {
  cat("✓ SUCCESS - All modules executed without errors!\n\n")
} else {
  cat("⚠️  WARNING - Some modules encountered errors.\n")
  cat("    Check EXECUTION_LOG.csv for details.\n\n")
}

cat("Project Summary:\n")
cat("  • Project:", PROJECT_NAME, "\n")
cat("  • Analysis Year:", ANALYSIS_YEAR, "\n")
cat("  • Total Duration:", sprintf("%.1f minutes", TOTAL_DURATION), "\n")
cat("  • Completion Time:", format(END_TIME, "%Y-%m-%d %H:%M:%S"), "\n\n")

cat("═══════════════════════════════════════════════════════════════════\n\n")

# Clean up memory
rm(modules, execution_log, output_files, csv_files, rdata_files, 
   html_files, png_files, txt_files, required_files, missing_files)

cat("✨ Ready to explore your analysis results! ✨\n\n")
