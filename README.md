[English](README.md) | [简体中文](README_zh.md)

# Global Dog Parks Analysis

This project analyzes dog-park accessibility and urban livability across 100+ countries using OpenStreetMap-based park data and comparative indicators.

## Project Scope

- Countries analyzed: 100+
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
3. Open 3_output/global_dog_parks_dashboard.html in your browser.

## Python Collection Modes

The Python collector is unified in 1_python_data_collection/api_global_mega.py.

- Full run (all ISO code elements):
	- python 1_python_data_collection/api_global_mega.py --mode full
- Targeted recovery for US and HK (merge into existing output files):
	- python 1_python_data_collection/api_global_mega.py --mode targeted
- Targeted recovery for HK only:
	- python 1_python_data_collection/api_global_mega.py --mode targeted --only-hk
- Targeted recovery for US only:
	- python 1_python_data_collection/api_global_mega.py --mode targeted --only-us

The targeted mode updates existing output files in-place and refreshes coverage status.

## ISO 3166-1 Scope Definition

This project uses ISO 3166-1 alpha-2 code elements as the global country/region scope.

- Scope basis: code elements for countries and territories
- Current total in this workflow: 249
- Important note: this is not the same as sovereign-state counts

This definition is automatically written into output metadata:

- 3_output/dashboard/pet_parks_by_country.geojson (FeatureCollection properties)
- 3_output/dashboard/dataset_metadata.json (structured metadata summary)

## Key Output Files

- 3_output/dashboard/pet_parks_by_country.csv: latest mega collector CSV output
- 3_output/dashboard/pet_parks_by_country.geojson: latest mega collector GeoJSON output
- 3_output/dashboard/country_coverage_report.csv: latest coverage status by ISO code
- 3_output/dashboard/dataset_metadata.json: ISO scope definition and run summary
- 3_output/global_dog_parks_dashboard.html: interactive dashboard

Historical generated files previously stored under 3_output have been archived to:

- 0_cache/3_output_archive_20260510

## Methodology Summary

- Data source: OpenStreetMap dog-park related tags (aggregated at country level)
- Normalization: per-100k population metrics
- Comparative scoring: scaled indicators for cross-country ranking
- Segmentation: K-means clustering for country groups

## Limitations

- OSM coverage is uneven across countries
- Data quality depends on tag completeness and geocoding consistency
- Results should be interpreted as comparative and directional, not causal proof

## Maintenance

- Last major update: May 2026
- Recommended: rerun the pipeline when source data is refreshed
