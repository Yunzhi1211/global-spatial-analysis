[English](README.md) | [简体中文](README_zh.md)

# Global Dog Parks Analysis

This project analyzes dog-park accessibility and urban livability across 195+ countries using OpenStreetMap-based park data and comparative indicators.

## Project Scope

- Countries analyzed: 195+
- Analysis level: country-level global comparison
- Core indicator: dog parks per 100,000 population
- Key outputs: ranking tables, regional profiles, clustering results, interactive dashboard

## Repository Structure

- 0_cache: cached data, historical scripts, and local utilities
- 1_python_data_collection: Python data collection scripts
- 2_R_script: global analysis pipeline in R
- 3_output: generated datasets, reports, and dashboard assets

## Analysis Pipeline

- 00_setup.R: environment setup and shared helper configuration
- 01_global_data_integration.R: country-level aggregation and master dataset creation
- 02_exploratory_analysis_global.R: descriptive and regional exploratory analysis
- 03_regional_analysis.R: regional differences and peer-country profiling
- 04_global_ranking.R: global ranking and tier classification
- 05_country_clustering.R: K-means clustering and profile segmentation
- 06_interactive_global_dashboard.R: dashboard-oriented outputs
- RUN_ALL_ANALYSIS_GLOBAL.R: end-to-end runner

## Quick Start

1. Open this workspace in VS Code or RStudio.
2. Run 2_R_script/RUN_ALL_ANALYSIS_GLOBAL.R for full pipeline execution.
3. Open 3_output/10_fancy_dashboard.html in your browser.

## Key Output Files

- 3_output/01_master_global_dataset.csv: integrated master dataset
- 3_output/04_global_ranking_full.csv: full country ranking
- 3_output/03_peer_country_groups.csv: peer-country mapping
- 3_output/05_country_clusters_kmeans.csv: clustering results
- 3_output/10_fancy_dashboard.html: interactive dashboard

## Methodology Summary

- Data source: OpenStreetMap dog-park related tags (aggregated at country level)
- Normalization: per-100k population metrics
- Comparative scoring: scaled indicators for cross-country ranking
- Segmentation: K-means clustering for country groups

## Current AI Insights Note

The AI Insights section in the dashboard currently uses local JavaScript template generation based on selected countries and existing dataset fields. It is not connected to a live LLM API by default.

## Limitations

- OSM coverage is uneven across countries
- Data quality depends on tag completeness and geocoding consistency
- Results should be interpreted as comparative and directional, not causal proof

## Maintenance

- Last major update: 2026
- Recommended: rerun the pipeline when source data is refreshed
