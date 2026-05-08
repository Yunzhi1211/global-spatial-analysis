# ============================================================================
# RUN_ALL_ANALYSIS_GLOBAL.R
# Master Control Script - Global Analysis Pipeline
# ============================================================================
# This script executes the entire global dog parks analysis workflow:
#   1. Global Data Integration
#   2. Exploratory Data Analysis
#   3. Regional & Peer Analysis
#   4. Global Ranking Analysis
#   5. Country Clustering
#   6. Interactive Dashboard
# ============================================================================

# Ensure we're in the correct working directory (2_R_script folder)
# This script should be run from the 2_R_script directory
current_dir <- basename(getwd())
if (current_dir != "2_R_script") {
  # Try to set to 2_R_script if we're in parent directory
  if (dir.exists("2_R_script")) {
    setwd("2_R_script")
    cat("✓ Changed working directory to: 2_R_script\n\n")
  } else if (!file.exists("00_setup.R")) {
    stop("Error: Cannot find 00_setup.R. Please run from project root or 2_R_script directory.")
  }
}

cat("Current working directory:", getwd(), "\n")

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                                                                ║\n")
cat("║     GLOBAL DOG PARKS ANALYSIS - COMPLETE PIPELINE              ║\n")
cat("║     Worldwide Coverage (195+ countries)                        ║\n")
cat("║                                                                ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

start_time <- Sys.time()

# ============================================================================
# MODULE 1: SETUP & CONFIGURATION
# ============================================================================
cat("──────────────────────────────────────────────────────────────────\n")
cat("STEP 0: Setting up analysis environment...\n")
cat("──────────────────────────────────────────────────────────────────\n")

tryCatch({
  source("00_setup.R")
  cat("✓ Setup completed successfully\n\n")
}, error = function(e) {
  cat("✗ Setup failed:", e$message, "\n\n")
  stop(e)
})

# ============================================================================
# MODULE 2: GLOBAL DATA INTEGRATION
# ============================================================================
cat("──────────────────────────────────────────────────────────────────\n")
cat("STEP 1: Global Data Integration\n")
cat("──────────────────────────────────────────────────────────────────\n")
step1_start <- Sys.time()

tryCatch({
  source("01_global_data_integration.R")
  step1_time <- difftime(Sys.time(), step1_start, units = "secs")
  cat(sprintf("✓ Step 1 completed in %.1f seconds\n\n", step1_time))
}, error = function(e) {
  cat("✗ Step 1 failed:", e$message, "\n\n")
  stop(e)
})

# ============================================================================
# MODULE 3: EXPLORATORY DATA ANALYSIS
# ============================================================================
cat("──────────────────────────────────────────────────────────────────\n")
cat("STEP 2: Exploratory Data Analysis (Global)\n")
cat("──────────────────────────────────────────────────────────────────\n")
step2_start <- Sys.time()

tryCatch({
  source("02_exploratory_analysis_global.R")
  step2_time <- difftime(Sys.time(), step2_start, units = "secs")
  cat(sprintf("✓ Step 2 completed in %.1f seconds\n\n", step2_time))
}, error = function(e) {
  cat("✗ Step 2 failed:", e$message, "\n\n")
  stop(e)
})

# ============================================================================
# MODULE 4: REGIONAL & PEER ANALYSIS
# ============================================================================
cat("──────────────────────────────────────────────────────────────────\n")
cat("STEP 3: Regional & Peer Analysis\n")
cat("──────────────────────────────────────────────────────────────────\n")
step3_start <- Sys.time()

tryCatch({
  source("03_regional_analysis.R")
  step3_time <- difftime(Sys.time(), step3_start, units = "secs")
  cat(sprintf("✓ Step 3 completed in %.1f seconds\n\n", step3_time))
}, error = function(e) {
  cat("✗ Step 3 failed:", e$message, "\n\n")
  stop(e)
})

# ============================================================================
# MODULE 5: GLOBAL RANKING ANALYSIS
# ============================================================================
cat("──────────────────────────────────────────────────────────────────\n")
cat("STEP 4: Global Ranking Analysis\n")
cat("──────────────────────────────────────────────────────────────────\n")
step4_start <- Sys.time()

tryCatch({
  source("04_global_ranking.R")
  step4_time <- difftime(Sys.time(), step4_start, units = "secs")
  cat(sprintf("✓ Step 4 completed in %.1f seconds\n\n", step4_time))
}, error = function(e) {
  cat("✗ Step 4 failed:", e$message, "\n\n")
  stop(e)
})

# ============================================================================
# MODULE 6: COUNTRY CLUSTERING
# ============================================================================
cat("──────────────────────────────────────────────────────────────────\n")
cat("STEP 5: Country Clustering & Peer Groups\n")
cat("──────────────────────────────────────────────────────────────────\n")
step5_start <- Sys.time()

tryCatch({
  source("05_country_clustering.R")
  step5_time <- difftime(Sys.time(), step5_start, units = "secs")
  cat(sprintf("✓ Step 5 completed in %.1f seconds\n\n", step5_time))
}, error = function(e) {
  cat("✗ Step 5 failed:", e$message, "\n\n")
  stop(e)
})

# ============================================================================
# MODULE 7: INTERACTIVE DASHBOARD
# ============================================================================
cat("──────────────────────────────────────────────────────────────────\n")
cat("STEP 6: Interactive Global Dashboard\n")
cat("──────────────────────────────────────────────────────────────────\n")
step6_start <- Sys.time()

tryCatch({
  source("06_interactive_global_dashboard.R")
  step6_time <- difftime(Sys.time(), step6_start, units = "secs")
  cat(sprintf("✓ Step 6 completed in %.1f seconds\n\n", step6_time))
}, error = function(e) {
  cat("✗ Step 6 failed:", e$message, "\n\n")
  stop(e)
})

# ============================================================================
# ANALYSIS COMPLETE - SUMMARY REPORT
# ============================================================================
total_time <- difftime(Sys.time(), start_time, units = "secs")

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║                                                                ║\n")
cat("║            ✓ ANALYSIS PIPELINE COMPLETED SUCCESSFULLY          ║\n")
cat("║                                                                ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("EXECUTION SUMMARY:\n")
cat("──────────────────────────────────────────────────────────────────\n")
cat(sprintf("Total execution time: %.1f seconds (%.1f minutes)\n\n", total_time, total_time/60))

cat("MODULES COMPLETED:\n")
cat(sprintf("  [✓] 00_setup.R                          - Configuration\n"))
cat(sprintf("  [✓] 01_global_data_integration.R        - %.1f sec\n", step1_time))
cat(sprintf("  [✓] 02_exploratory_analysis_global.R    - %.1f sec\n", step2_time))
cat(sprintf("  [✓] 03_regional_analysis.R              - %.1f sec\n", step3_time))
cat(sprintf("  [✓] 04_global_ranking.R                 - %.1f sec\n", step4_time))
cat(sprintf("  [✓] 05_country_clustering.R             - %.1f sec\n", step5_time))
cat(sprintf("  [✓] 06_interactive_global_dashboard.R   - %.1f sec\n", step6_time))

cat("\n")
cat("OUTPUT LOCATION:\n")
cat("──────────────────────────────────────────────────────────────────\n")
cat(sprintf("Analysis results saved to: %s\n\n", dir_analysis))

cat("KEY OUTPUT FILES:\n")
cat("──────────────────────────────────────────────────────────────────\n")
cat("DATA FILES:\n")
cat("  • 01_master_global_dataset.csv\n")
cat("  • 02_global_descriptive_statistics.csv\n")
cat("  • 03_regional_detailed_analysis.csv\n")
cat("  • 04_global_ranking_full.csv\n")
cat("  • 05_country_clusters_kmeans.csv\n")
cat("  • 06_complete_dashboard_data.csv\n\n")

cat("VISUALIZATION FILES:\n")
cat("  • 15+ PNG charts (distribution, rankings, clusters)\n")
cat("  • All saved to: figures/\n\n")

cat("INTERACTIVE DASHBOARD:\n")
cat("  • 06_global_interactive_dashboard.html\n")
cat("  • Open in web browser for interactive exploration\n\n")

cat("INSIGHTS & REPORTS:\n")
cat("  • 02_eda_findings.txt\n")
cat("  • 03_regional_analysis_report.txt\n")
cat("  • 04_ranking_summary.txt\n")
cat("  • 05_clustering_summary.txt\n")
cat("  • 06_dashboard_insights.txt\n\n")

cat("NEXT STEPS:\n")
cat("──────────────────────────────────────────────────────────────────\n")
cat("1. Review interactive dashboard: Open 06_global_interactive_dashboard.html\n")
cat("2. Examine country rankings: Check 04_global_ranking_full.csv\n")
cat("3. Identify peer groups: See 05_global_peer_groups.csv\n")
cat("4. Analyze by region: Review regional_detailed_analysis.csv\n")
cat("5. View all insights: Read text reports in analysis_results_global/\n\n")

cat("DATA INSIGHTS:\n")
cat("──────────────────────────────────────────────────────────────────\n")

# Load and display summary stats
if (file.exists(file.path(dir_analysis, "01_master_global_dataset.csv"))) {
  summary_data <- read_csv(file.path(dir_analysis, "01_master_global_dataset.csv"),
                          show_col_types = FALSE)

  cat(sprintf("Countries analyzed:           %d\n", nrow(summary_data)))
  cat(sprintf("Total dog parks:              %d\n", sum(summary_data$n_parks)))
  cat(sprintf("Average parks per 100k:       %.2f\n", mean(summary_data$parks_per_100k, na.rm = TRUE)))
  cat(sprintf("Regions covered:              %d\n", n_distinct(summary_data$region)))
  cat(sprintf("Development tiers identified: 5\n"))
  cat(sprintf("Peer clusters:                5\n\n"))
}

cat("═══════════════════════════════════════════════════════════════════\n")
cat("Analysis completed at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

