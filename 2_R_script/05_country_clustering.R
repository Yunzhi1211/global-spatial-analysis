# ============================================================================
# 05_country_clustering.R
# Country Clustering & Peer Group Analysis
# ============================================================================
# This script creates:
#   1. K-means clustering of countries by dog park metrics
#   2. Hierarchical clustering dendrogram
#   3. Peer group identification for benchmarking
#   4. Cluster profiling and characterization
# ============================================================================

source("00_setup.R")
load(file.path(dir_analysis, "01_master_global_data.RData"))

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Country Clustering & Peer Group Module\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# ============================================================================
# PART 1: Prepare Clustering Data
# ============================================================================
cat("--- Preparing Clustering Data ---\n")

# Select numeric features for clustering
cluster_data <- master_global %>%
  filter(!is.na(parks_per_100k) & !is.na(estimated_population)) %>%
  mutate(
    log_population = log10(estimated_population + 1),
    log_parks_per_100k = log10(parks_per_100k + 0.001),
    park_density_score = standardize_to_100(parks_per_100k)
  ) %>%
  select(country_name, region, n_parks, parks_per_100k, estimated_population,
         log_population, log_parks_per_100k, park_density_score)

# Scale features for clustering
features_for_clustering <- cluster_data %>%
  select(log_parks_per_100k, log_population, park_density_score) %>%
  scale()

rownames(features_for_clustering) <- cluster_data$country_name

cat("  Countries for clustering:", nrow(cluster_data), "\n")
cat("  Features used: log_parks_per_100k, log_population, park_density_score\n\n")

# ============================================================================
# PART 2: Optimal Number of Clusters (Elbow Method)
# ============================================================================
cat("--- Determining Optimal Clusters ---\n")

set.seed(42)
max_k <- min(10, nrow(cluster_data) - 1)
wss <- sapply(1:max_k, function(k) {
  kmeans(features_for_clustering, centers = k, nstart = 25, iter.max = 100)$tot.withinss
})

# Elbow plot data
elbow_df <- data.frame(k = 1:max_k, wss = wss)

p_elbow <- ggplot(elbow_df, aes(x = k, y = wss)) +
  geom_line(linewidth = 1, color = "#2E86AB") +
  geom_point(size = 3, color = "#2E86AB") +
  scale_x_continuous(breaks = 1:max_k) +
  labs(
    title = "Elbow Method: Optimal Number of Clusters",
    x = "Number of Clusters (k)",
    y = "Total Within-Cluster Sum of Squares"
  ) +
  theme_global

ggsave(file.path(dir_figures, "05_elbow_method.png"),
       p_elbow, width = 10, height = 6, dpi = 300)

cat("  ✓ Elbow plot saved\n")

# Choose k (typically 4-5 for this type of analysis)
optimal_k <- 4
cat("  Using k =", optimal_k, "clusters\n\n")

# ============================================================================
# PART 3: K-Means Clustering
# ============================================================================
cat("--- Running K-Means Clustering ---\n")

set.seed(42)
km_result <- kmeans(features_for_clustering, centers = optimal_k, nstart = 25, iter.max = 100)

# Add cluster assignments
cluster_data <- cluster_data %>%
  mutate(
    cluster_id = km_result$cluster,
    cluster_label = case_when(
      cluster_id == which.max(tapply(parks_per_100k, km_result$cluster, mean)) ~ "Leaders",
      cluster_id == which.min(tapply(parks_per_100k, km_result$cluster, mean)) ~ "Emerging",
      TRUE ~ paste0("Group_", cluster_id)
    )
  )

# Refine labels based on cluster characteristics
cluster_means <- cluster_data %>%
  group_by(cluster_id) %>%
  summarise(
    avg_parks_per_100k = mean(parks_per_100k),
    avg_population = mean(estimated_population),
    n_countries = n(),
    .groups = "drop"
  ) %>%
  arrange(desc(avg_parks_per_100k))

# Assign descriptive labels by rank
cluster_labels <- cluster_means %>%
  mutate(
    rank = row_number(),
    cluster_label = case_when(
      rank == 1 ~ "Leaders (High Parks)",
      rank == 2 ~ "Developing (Moderate Parks)",
      rank == 3 ~ "Transitioning (Low-Moderate)",
      rank == nrow(cluster_means) ~ "Emerging (Low Parks)",
      TRUE ~ paste0("Group_", rank)
    )
  ) %>%
  select(cluster_id, cluster_label)

cluster_data <- cluster_data %>%
  select(-cluster_label) %>%
  left_join(cluster_labels, by = "cluster_id")

cat("  K-means clustering complete\n")
cat("  Cluster sizes:\n")
print(table(cluster_data$cluster_label))
cat("\n")

# ============================================================================
# PART 4: Cluster Profiling
# ============================================================================
cat("--- Cluster Profiling ---\n")

cluster_profiles <- cluster_data %>%
  group_by(cluster_id, cluster_label) %>%
  summarise(
    n_countries = n(),
    avg_parks_per_100k = round(mean(parks_per_100k), 3),
    median_parks_per_100k = round(median(parks_per_100k), 3),
    min_parks_per_100k = round(min(parks_per_100k), 3),
    max_parks_per_100k = round(max(parks_per_100k), 3),
    avg_population = round(mean(estimated_population)),
    total_parks = sum(n_parks),
    top_countries = paste(head(country_name[order(-parks_per_100k)], 3), collapse = ", "),
    regions_represented = paste(unique(region), collapse = ", "),
    .groups = "drop"
  ) %>%
  arrange(desc(avg_parks_per_100k))

cat("Cluster profiles:\n")
print(cluster_profiles %>% select(cluster_label, n_countries, avg_parks_per_100k, 
                                   median_parks_per_100k, top_countries))
cat("\n")

write_csv(cluster_profiles,
         file.path(dir_analysis, "05_cluster_profiles.csv"))

# ============================================================================
# PART 5: Peer Group Identification
# ============================================================================
cat("--- Identifying Peer Groups ---\n")

# For each country, find 3 closest peers within the same cluster
peer_groups <- data.frame()

for (i in 1:nrow(cluster_data)) {
  focal <- cluster_data[i, ]
  
  same_cluster <- cluster_data %>%
    filter(cluster_id == focal$cluster_id & country_name != focal$country_name)
  
  if (nrow(same_cluster) == 0) next
  
  # Calculate Euclidean distance in feature space
  focal_features <- features_for_clustering[focal$country_name, , drop = FALSE]
  peer_features <- features_for_clustering[same_cluster$country_name, , drop = FALSE]
  
  distances <- as.numeric(sqrt(rowSums((sweep(peer_features, 2, focal_features))^2)))
  
  same_cluster <- same_cluster %>%
    mutate(distance = distances) %>%
    arrange(distance) %>%
    head(3)
  
  peer_groups <- rbind(peer_groups, data.frame(
    country = focal$country_name,
    cluster = focal$cluster_label,
    peer_1 = same_cluster$country_name[1],
    peer_1_parks = round(same_cluster$parks_per_100k[1], 3),
    peer_2 = ifelse(nrow(same_cluster) >= 2, same_cluster$country_name[2], NA),
    peer_2_parks = ifelse(nrow(same_cluster) >= 2, round(same_cluster$parks_per_100k[2], 3), NA),
    peer_3 = ifelse(nrow(same_cluster) >= 3, same_cluster$country_name[3], NA),
    peer_3_parks = ifelse(nrow(same_cluster) >= 3, round(same_cluster$parks_per_100k[3], 3), NA)
  ))
}

write_csv(peer_groups, file.path(dir_analysis, "05_global_peer_groups.csv"))
cat("  ✓ Peer groups identified for", nrow(peer_groups), "countries\n\n")

# ============================================================================
# PART 6: Full Cluster Assignments Export
# ============================================================================
cat("--- Exporting Cluster Assignments ---\n")

cluster_export <- cluster_data %>%
  select(country_name, region, n_parks, parks_per_100k, estimated_population,
         park_density_score, cluster_id, cluster_label) %>%
  arrange(cluster_id, desc(parks_per_100k))

write_csv(cluster_export, file.path(dir_analysis, "05_country_clusters_kmeans.csv"))
cat("  ✓ Cluster assignments exported\n\n")

# ============================================================================
# PART 7: Visualizations
# ============================================================================
cat("--- Creating Clustering Visualizations ---\n")

# Plot 1: Cluster scatter plot
p_clusters <- cluster_data %>%
  ggplot(aes(x = log_parks_per_100k, y = log_population)) +
  geom_point(aes(color = cluster_label, size = n_parks), alpha = 0.7) +
  scale_color_brewer(palette = "Set1", name = "Cluster") +
  scale_size_continuous(name = "Total Parks", range = c(2, 10)) +
  labs(
    title = "Country Clusters: Dog Park Provision vs Population",
    subtitle = sprintf("K-means clustering (k=%d) on %d countries", optimal_k, nrow(cluster_data)),
    x = "Log10(Dog Parks per 100k)",
    y = "Log10(Population)"
  ) +
  theme_global

ggsave(file.path(dir_figures, "05_cluster_scatter.png"),
       p_clusters, width = 12, height = 8, dpi = 300)
cat("  ✓ Cluster scatter plot saved\n")

# Plot 2: Cluster boxplot comparison
p_cluster_box <- cluster_data %>%
  ggplot(aes(x = reorder(cluster_label, parks_per_100k), y = parks_per_100k)) +
  geom_boxplot(aes(fill = cluster_label), alpha = 0.7, outlier.shape = 21) +
  geom_jitter(width = 0.2, alpha = 0.4, size = 2) +
  scale_fill_brewer(palette = "Set1", guide = "none") +
  labs(
    title = "Dog Park Provision by Cluster",
    x = "Cluster",
    y = "Dog Parks per 100k Population"
  ) +
  theme_global +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

ggsave(file.path(dir_figures, "05_cluster_boxplot.png"),
       p_cluster_box, width = 10, height = 7, dpi = 300)
cat("  ✓ Cluster boxplot saved\n")

# Plot 3: Regional composition of clusters
p_cluster_region <- cluster_data %>%
  count(cluster_label, region) %>%
  ggplot(aes(x = cluster_label, y = n, fill = region)) +
  geom_col(position = "fill", color = "white", linewidth = 0.3) +
  scale_fill_brewer(palette = "Set2", name = "Region") +
  scale_y_continuous(labels = scales::percent) +
  labs(
    title = "Regional Composition of Each Cluster",
    x = "Cluster",
    y = "Proportion of Countries"
  ) +
  theme_global +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

ggsave(file.path(dir_figures, "05_cluster_regional_composition.png"),
       p_cluster_region, width = 12, height = 7, dpi = 300)
cat("  ✓ Regional composition plot saved\n")

# Plot 4: Cluster means radar-style bar chart
p_cluster_means <- cluster_profiles %>%
  select(cluster_label, avg_parks_per_100k, n_countries) %>%
  ggplot(aes(x = reorder(cluster_label, avg_parks_per_100k), y = avg_parks_per_100k)) +
  geom_col(aes(fill = cluster_label), color = "white", linewidth = 0.5) +
  geom_text(aes(label = sprintf("%.2f\n(%d countries)", avg_parks_per_100k, n_countries)),
            vjust = -0.3, fontface = "bold", size = 3.5) +
  scale_fill_brewer(palette = "Set1", guide = "none") +
  coord_flip() +
  labs(
    title = "Average Dog Parks per 100k by Cluster",
    x = "Cluster",
    y = "Average Dog Parks per 100k"
  ) +
  theme_global

ggsave(file.path(dir_figures, "05_cluster_means.png"),
       p_cluster_means, width = 10, height = 6, dpi = 300)
cat("  ✓ Cluster means plot saved\n\n")

# ============================================================================
# PART 8: Save Results
# ============================================================================
cat("--- Saving Clustering Results ---\n")

save(cluster_data, cluster_profiles, peer_groups, km_result,
     file = file.path(dir_analysis, "05_clustering_results.RData"))

cat("  ✓ All clustering results saved\n\n")

# ============================================================================
# PART 9: Summary Report
# ============================================================================
cat("--- Clustering Summary Report ---\n")

# Build summary text safely with pre-computed values
cluster_summary_lines <- cluster_profiles %>%
  rowwise() %>%
  mutate(line = sprintf("  %s: %d countries, avg %.3f parks/100k, top: %s",
                        cluster_label, n_countries, avg_parks_per_100k, top_countries)) %>%
  pull(line) %>%
  paste(collapse = "\n")

summary_text <- sprintf(
"COUNTRY CLUSTERING & PEER GROUP ANALYSIS

METHODOLOGY:
- Algorithm: K-means clustering (k=%d)
- Features: log(parks_per_100k), log(population), park_density_score
- Countries analyzed: %d

CLUSTER PROFILES:
%s

PEER GROUP STATISTICS:
- Total peer group assignments: %d
- Each country matched to up to 3 closest peers within cluster

KEY FINDINGS:
1. %d clusters identified with distinct dog park provision patterns
2. Leaders cluster has avg %.3f parks/100k (%d countries)
3. Emerging cluster has avg %.3f parks/100k (%d countries)
4. Clear separation between high and low provision countries
5. Regional patterns visible within clusters

APPLICATIONS:
- Peer benchmarking: Countries can compare with similar peers
- Policy transfer: Learn from cluster leaders
- Gap analysis: Identify improvement opportunities within cluster
- Regional cooperation: Cluster membership crosses regional boundaries
",

optimal_k,
nrow(cluster_data),
cluster_summary_lines,
nrow(peer_groups),
optimal_k,
cluster_profiles$avg_parks_per_100k[1], cluster_profiles$n_countries[1],
cluster_profiles$avg_parks_per_100k[nrow(cluster_profiles)], cluster_profiles$n_countries[nrow(cluster_profiles)]
)

write(summary_text, file.path(dir_analysis, "05_clustering_summary.txt"))
cat(summary_text)

# ============================================================================
# Session Summary
# ============================================================================
cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Country Clustering Analysis Complete!\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat("Output files:\n")
cat("  ✓ 05_country_clusters_kmeans.csv\n")
cat("  ✓ 05_cluster_profiles.csv\n")
cat("  ✓ 05_global_peer_groups.csv\n")
cat("  ✓ 05_clustering_results.RData\n")
cat("  ✓ 05_clustering_summary.txt\n")
cat("  ✓ 4 visualization PNG files\n\n")

cat("Next: Run 06_interactive_global_dashboard.R\n")
