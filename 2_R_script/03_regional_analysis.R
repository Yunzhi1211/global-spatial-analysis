# ============================================================================
# 03_regional_analysis.R
# Regional & Peer Analysis - Worldwide Dog Parks
# ============================================================================
# This script analyzes:
#   1. Regional patterns and disparities
#   2. Peer country identification within regions
#   3. Development trajectory analysis
#   4. Cross-regional comparisons
# ============================================================================

source("00_setup.R")
load(file.path(dir_analysis, "01_master_global_data.RData"))

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Regional & Peer Analysis Module\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# ============================================================================
# PART 1: Regional Performance Metrics
# ============================================================================
cat("--- Calculating Regional Performance Metrics ---\n")

regional_detailed <- master_global %>%
  group_by(region) %>%
  summarise(
    # Quantity metrics
    n_countries = n(),
    total_parks = sum(n_parks),
    total_population = sum(estimated_population),
    
    # Per-capita metrics
    mean_parks_per_100k = mean(parks_per_100k, na.rm = TRUE),
    median_parks_per_100k = median(parks_per_100k, na.rm = TRUE),
    sd_parks_per_100k = sd(parks_per_100k, na.rm = TRUE),
    
    # Equity metrics
    parks_gini = gini(parks_per_100k),  # Gini coefficient for inequality
    
    # Score
    regional_score = mean(park_density_score, na.rm = TRUE),
    
    .groups = "drop"
  ) %>%
  arrange(desc(regional_score))

# Add best/worst performers separately (easier logic)
regional_detailed <- regional_detailed %>%
  rowwise() %>%
  mutate(
    best_performer = master_global %>%
      filter(region == region) %>%
      arrange(desc(parks_per_100k)) %>%
      slice(1) %>%
      pull(country_name),
    worst_performer = master_global %>%
      filter(region == region) %>%
      arrange(parks_per_100k) %>%
      slice(1) %>%
      pull(country_name)
  ) %>%
  ungroup()

write_csv(regional_detailed,
         file.path(dir_analysis, "03_regional_detailed_analysis.csv"))

cat("✓ Regional performance calculated\n\n")
print(regional_detailed %>% select(-best_performer, -worst_performer))
cat("\n")

# ============================================================================
# PART 2: Peer Country Groups (Within-Region Clustering)
# ============================================================================
cat("--- Identifying Peer Country Groups ---\n")

peer_analysis <- master_global %>%
  group_by(region) %>%
  mutate(
    # Quartile ranking within region
    region_quartile = ntile(parks_per_100k, 4),
    region_quartile_label = case_when(
      region_quartile == 4 ~ "Regional Leader",
      region_quartile == 3 ~ "Above Average",
      region_quartile == 2 ~ "Below Average",
      TRUE ~ "Regional Laggard"
    ),
    
    # Peer group: countries similar in development
    region_rank = rank(-parks_per_100k),
    peers = NA_character_
  ) %>%
  ungroup() %>%
  arrange(region, desc(parks_per_100k))

# Identify peers for each country
for (i in 1:nrow(peer_analysis)) {
  current_region <- peer_analysis$region[i]
  current_score <- peer_analysis$parks_per_100k[i]
  
  peers <- peer_analysis %>%
    filter(region == current_region,
           country_name != peer_analysis$country_name[i]) %>%
    mutate(score_diff = abs(parks_per_100k - current_score)) %>%
    slice_min(score_diff, n = 3) %>%
    pull(country_name) %>%
    paste(collapse = ", ")
  
  peer_analysis$peers[i] <- peers
}

write_csv(peer_analysis %>% select(country_name, region, parks_per_100k, 
                                   region_quartile_label, peers),
         file.path(dir_analysis, "03_peer_country_groups.csv"))

cat("✓ Peer country groups identified\n\n")

# ============================================================================
# PART 3: Regional Leader & Laggard Analysis
# ============================================================================
cat("--- Regional Leaders and Laggards ---\n")

leaders_laggards <- peer_analysis %>%
  group_by(region) %>%
  summarise(
    # Gap between leaders and laggards
    leader_score = max(parks_per_100k, na.rm = TRUE),
    laggard_score = min(parks_per_100k, na.rm = TRUE),
    regional_gap = leader_score - laggard_score,
    gap_ratio = leader_score / (laggard_score + 1),  # +1 to avoid division by zero
    .groups = "drop"
  ) %>%
  arrange(desc(gap_ratio))

# Add leaders and laggards separately (outside of summarise)
leaders_laggards <- leaders_laggards %>%
  rowwise() %>%
  mutate(
    # Top 3 performers
    leaders = paste(
      peer_analysis %>%
        filter(region == region) %>%
        arrange(desc(parks_per_100k)) %>%
        slice(1:3) %>%
        pull(country_name),
      collapse = " | "
    ),
    # Bottom 3 performers
    laggards = paste(
      peer_analysis %>%
        filter(region == region) %>%
        arrange(parks_per_100k) %>%
        slice(1:3) %>%
        pull(country_name),
      collapse = " | "
    )
  ) %>%
  ungroup()

write_csv(leaders_laggards,
         file.path(dir_analysis, "03_leaders_laggards.csv"))

cat("Regional Leaders and Laggards:\n")
print(leaders_laggards)
cat("\n")

# ============================================================================
# PART 4: Cross-Regional Benchmarking
# ============================================================================
cat("--- Cross-Regional Benchmarking Analysis ---\n")

benchmarking <- master_global %>%
  group_by(region) %>%
  mutate(
    # Rank against global average
    vs_global_mean = parks_per_100k - mean(master_global$parks_per_100k, na.rm = TRUE),
    vs_global_median = parks_per_100k - median(master_global$parks_per_100k, na.rm = TRUE),
    
    # Position in regional ranking
    regional_position = rank(-parks_per_100k, ties.method = "average"),
    
    # Potential gap (difference from regional leader)
    regional_leader = max(parks_per_100k, na.rm = TRUE),
    gap_to_leader = regional_leader - parks_per_100k,
    pct_of_leader = (parks_per_100k / regional_leader) * 100,
    
    .groups = "drop"
  )

# Top countries across regions for different metrics
cat("TOP PERFORMERS BY METRIC:\n")
cat("\nGlobal Parks per 100k:\n")
print(head(benchmarking %>% select(country_name, region, parks_per_100k), 10))

cat("\nMost Improved Potential (Gap to Leader):\n")
print(head(benchmarking %>% 
           arrange(gap_to_leader) %>% 
           select(country_name, region, gap_to_leader, pct_of_leader), 10))

cat("\n")

# ============================================================================
# PART 5: Visualizations - Regional Analysis
# ============================================================================
cat("--- Creating Regional Visualizations ---\n")

# Plot 1: Regional ranking
p_regional_rank <- regional_detailed %>%
  ggplot(aes(x = reorder(region, regional_score), y = regional_score)) +
  geom_col(aes(fill = region), color = "white", linewidth = 0.5, alpha = 0.8) +
  scale_fill_manual(values = palette_regions, guide = "none") +
  geom_label(aes(label = sprintf("%.1f", regional_score)), vjust = -0.5, fontface = "bold") +
  coord_flip() +
  labs(
    title = "Regional Performance Score",
    x = "Region",
    y = "Average Park Density Score"
  ) +
  theme_global

ggsave(file.path(dir_figures, "03_regional_ranking.png"),
       p_regional_rank, width = 11, height = 6, dpi = 300)

cat("  ✓ Regional ranking saved\n")

# Plot 2: Quartile distribution by region
p_quartile <- peer_analysis %>%
  ggplot(aes(x = region, fill = region_quartile_label)) +
  geom_bar(color = "white", linewidth = 0.5) +
  scale_fill_brewer(palette = "RdYlGn", name = "Quartile", direction = -1) +
  labs(
    title = "Distribution of Countries by Performance Quartile (Within Region)",
    x = "Region",
    y = "Number of Countries"
  ) +
  theme_global +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(dir_figures, "03_quartile_distribution.png"),
       p_quartile, width = 12, height = 7, dpi = 300)

cat("  ✓ Quartile distribution saved\n")

# Plot 3: Regional gap analysis
p_gap <- leaders_laggards %>%
  ggplot(aes(x = reorder(region, gap_ratio), y = gap_ratio)) +
  geom_col(fill = "#E74C3C", color = "white", linewidth = 0.5, alpha = 0.8) +
  geom_label(aes(label = sprintf("%.1fx", gap_ratio)), vjust = -0.5, fontface = "bold") +
  coord_flip() +
  labs(
    title = "Regional Inequality: Gap Between Leaders and Laggards",
    x = "Region",
    y = "Gap Ratio (Leader / Laggard)"
  ) +
  theme_global

ggsave(file.path(dir_figures, "03_regional_gap_analysis.png"),
       p_gap, width = 11, height = 6, dpi = 300)

cat("  ✓ Gap analysis saved\n")

# Plot 4: Violin plot - distributions by region
p_violin <- master_global %>%
  ggplot(aes(x = region, y = parks_per_100k)) +
  geom_violin(aes(fill = region), alpha = 0.7, color = "grey40") +
  geom_boxplot(width = 0.1, alpha = 0.5) +
  geom_jitter(width = 0.15, alpha = 0.3, size = 2) +
  scale_fill_manual(values = palette_regions, guide = "none") +
  labs(
    title = "Distribution Variation Across Regions",
    x = "Region",
    y = "Dog Parks per 100k Population"
  ) +
  theme_global +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(dir_figures, "03_violin_regional_distribution.png"),
       p_violin, width = 12, height = 7, dpi = 300)

cat("  ✓ Violin plot saved\n\n")

# ============================================================================
# PART 6: Summary Report
# ============================================================================
cat("--- Regional Analysis Summary ---\n")

# Create gap_ratio mapping (unique by region)
gap_ratio_map <- leaders_laggards %>%
  select(region, gap_ratio) %>%
  distinct(region, .keep_all = TRUE)

# Prepare regional rankings text
regional_rankings_text <- regional_detailed %>%
  left_join(gap_ratio_map, by = "region") %>%
  rowwise() %>%
  mutate(
    ranking_line = sprintf("  %s: %.1f (n=%d countries, gap=%.1fx)", 
                           region, regional_score, n_countries, gap_ratio)
  ) %>%
  pull(ranking_line) %>%
  paste(collapse = "\n")

# Prepare leaders text
leaders_text <- head(leaders_laggards, 3) %>%
  rowwise() %>%
  mutate(leaders_line = sprintf("  %s: %s", region, leaders)) %>%
  pull(leaders_line) %>%
  paste(collapse = "\n")

# Prepare laggards text  
laggards_text <- tail(leaders_laggards, 3) %>%
  rowwise() %>%
  mutate(laggards_line = sprintf("  %s: %s", region, laggards)) %>%
  pull(laggards_line) %>%
  paste(collapse = "\n")

summary_report <- sprintf(
"REGIONAL & PEER ANALYSIS SUMMARY

GLOBAL REGIONS ANALYZED: %d
%s

REGIONAL RANKINGS (by Regional Score):
%s

KEY FINDINGS:

1. REGIONAL DISPARITIES:
   - Highest region score: %s (%.1f)
   - Lowest region score: %s (%.1f)
   - Score difference: %.1f points

2. INEQUALITY ANALYSIS:
   - Highest internal gap: %s (%.1fx difference)
   - Lowest internal gap: %s (%.1fx difference)
   - Average regional gap ratio: %.1fx

3. PEER DYNAMICS:
   - Each country has identified 3 most similar regional peers
   - Enables benchmarking and knowledge sharing within regions
   - Fastest improvement: Compare with regional peers

4. REGIONAL LEADERS:
%s

5. REGIONAL LAGGARDS:
%s

6. STRATEGIC INSIGHTS:
   - Opportunity for South-South cooperation within regions
   - Regional leaders can mentor laggards
   - Peer learning more effective than global comparison
   - Gap analysis shows potential for catch-up growth
",

nrow(regional_detailed),
paste(regional_detailed$region, collapse = ", "),
regional_rankings_text,

regional_detailed$region[1], regional_detailed$regional_score[1],
regional_detailed$region[nrow(regional_detailed)], regional_detailed$regional_score[nrow(regional_detailed)],
regional_detailed$regional_score[1] - regional_detailed$regional_score[nrow(regional_detailed)],

leaders_laggards$region[which.max(leaders_laggards$gap_ratio)], max(leaders_laggards$gap_ratio),
leaders_laggards$region[which.min(leaders_laggards$gap_ratio)], min(leaders_laggards$gap_ratio),
mean(leaders_laggards$gap_ratio),

leaders_text,
laggards_text
)

write(summary_report, file.path(dir_analysis, "03_regional_analysis_report.txt"))
cat(summary_report)

# ============================================================================
# Session Summary
# ============================================================================
cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Regional Analysis Complete!\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat("Output files:\n")
cat("  ✓ regional_detailed_analysis.csv\n")
cat("  ✓ peer_country_groups.csv\n")
cat("  ✓ leaders_laggards.csv\n")
cat("  ✓ 4 visualization PNG files\n")
cat("  ✓ regional_analysis_report.txt\n\n")

cat("Next: Run 04_global_ranking.R\n")
cat("═══════════════════════════════════════════════════════════════\n\n")
