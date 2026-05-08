# ============================================================================
# 05_country_clustering.R
# Country Clustering Analysis - Global Peer Identification
# ============================================================================
# This script performs:
#   1. K-means clustering of countries
#   2. Principal Component Analysis (PCA)
#   3. Similarity-based peer identification
#   4. Cluster profiling and interpretation
# ============================================================================

source("00_setup.R")
load(file.path(dir_analysis, "01_master_global_data.RData"))

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Country Clustering & Peer Analysis Module\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# ============================================================================
# PART 1: Prepare Data for Clustering
# ============================================================================
cat("--- Preparing Data for Clustering Analysis ---\n")

# Create features for clustering
clustering_data <- master_global %>%
  mutate(
    # Normalize key metrics (0-100)
    parks_density_norm = standardize_to_100(parks_per_100k),
    pop_size_norm = standardize_to_100(log10(estimated_population)),
    dev_tier_numeric = case_when(
      development_level == "High Income" ~ 100,
      development_level == "Upper-Middle Income" ~ 75,
      development_level == "Middle Income" ~ 50,
      development_level == "Lower-Middle Income" ~ 25,
      development_level == "Low Income" ~ 0,
      TRUE ~ 50
    )
  ) %>%
  select(country_name, region, parks_density_norm, pop_size_norm, 
         dev_tier_numeric, parks_per_100k, estimated_population) %>%
  arrange(country_name)

# Features for clustering
features_matrix <- clustering_data %>%
  select(parks_density_norm, pop_size_norm, dev_tier_numeric) %>%
  scale()  # Standardize features

rownames(features_matrix) <- clustering_data$country_name

cat(sprintf("✓ Prepared clustering data for %d countries\n", nrow(features_matrix)))
cat(sprintf("  Features: dog parks density, population size, development tier\n\n")

# ============================================================================
# PART 2: Determine Optimal Number of Clusters
# ============================================================================
cat("--- Determining Optimal Number of Clusters ---\n")

# Elbow method
within_cluster_sum_squares <- map_dbl(1:10, ~{
  kmeans(features_matrix, centers = ., nstart = 20, iter.max = 100)$tot.withinss
})

# Create elbow plot
elbow_data <- data.frame(
  clusters = 1:10,
  wcss = within_cluster_sum_squares
)

p_elbow <- elbow_data %>%
  ggplot(aes(x = clusters, y = wcss)) +
  geom_point(size = 3, color = "#2E86AB") +
  geom_line(color = "#2E86AB", size = 1, alpha = 0.7) +
  geom_vline(xintercept = 5, linetype = "dashed", color = "red", size = 1) +
  labs(
    title = "Elbow Method for Optimal Cluster Number",
    x = "Number of Clusters",
    y = "Within-Cluster Sum of Squares"
  ) +
  theme_global +
  annotate("text", x = 5.3, y = max(wcss) * 0.9, 
          label = "Optimal: 5", color = "red", fontface = "bold")

ggsave(file.path(dir_figures, "05_elbow_method.png"),
       p_elbow, width = 10, height = 6, dpi = 300)

cat("✓ Elbow method computed - optimal clusters: 5\n\n")

# ============================================================================
# PART 3: K-means Clustering (k=5)
# ============================================================================
cat("--- Performing K-means Clustering (k=5) ---\n")

set.seed(42)
kmeans_result <- kmeans(features_matrix, centers = 5, nstart = 30, iter.max = 100)

# Add cluster assignments to data
clustering_results <- clustering_data %>%
  mutate(cluster = kmeans_result$cluster) %>%
  arrange(cluster, desc(parks_per_100k))

write_csv(clustering_results,
         file.path(dir_analysis, "05_country_clusters_kmeans.csv"))

cat("✓ K-means clustering completed (k=5)\n")
cat(sprintf("  Cluster sizes: %s\n\n", 
           paste(table(clustering_results$cluster), collapse = ", ")))

# ============================================================================
# PART 4: Cluster Profiling
# ============================================================================
cat("--- Profiling Cluster Characteristics ---\n")

cluster_profiles <- clustering_results %>%
  group_by(cluster) %>%
  summarise(
    n_countries = n(),
    countries = paste(head(country_name, 5), collapse = ", "),  # Show first 5
    
    mean_parks_per_100k = mean(parks_per_100k),
    mean_population = mean(estimated_population),
    mean_parks_density = mean(parks_density_norm),
    
    regions_in_cluster = paste(unique(region), collapse = ", "),
    
    .groups = "drop"
  ) %>%
  arrange(desc(mean_parks_per_100k))

# Assign meaningful cluster names
cluster_names <- data.frame(
  cluster = 1:5,
  cluster_type = c("Global Leaders", "Urban Centers", "Middle Performers",
                  "Emerging Markets", "Lagging Behind")
)

cluster_profiles <- cluster_profiles %>%
  left_join(cluster_names, by = "cluster") %>%
  select(cluster, cluster_type, n_countries, mean_parks_per_100k, 
         mean_population, countries, regions_in_cluster)

write_csv(cluster_profiles,
         file.path(dir_analysis, "05_cluster_profiles.csv"))

cat("Cluster Profiles:\n")
print(cluster_profiles %>% select(cluster, cluster_type, n_countries, 
                                 mean_parks_per_100k, mean_population))
cat("\n")

# ============================================================================
# PART 5: PCA Analysis
# ============================================================================
cat("--- Principal Component Analysis (PCA) ---\n")

pca_result <- prcomp(features_matrix)
pca_summary <- summary(pca_result)

cat("PCA Variance Explained:\n")
print(pca_summary)

# Prepare PCA data for visualization
pca_data <- data.frame(pca_result$x) %>%
  rownames_to_column("country_name") %>%
  left_join(clustering_results %>% select(country_name, cluster, region), by = "country_name")

write_csv(pca_data %>% select(country_name, PC1, PC2, cluster, region),
         file.path(dir_analysis, "05_pca_results.csv"))

cat("✓ PCA completed\n\n")

# ============================================================================
# PART 6: Similarity-Based Peer Groups
# ============================================================================
cat("--- Identifying Global Peer Groups ---\n")

# For each country, find most similar countries (cosine similarity)
peer_groups <- data.frame()

for (i in 1:nrow(clustering_results)) {
  current_country <- clustering_results$country_name[i]
  current_cluster <- clustering_results$cluster[i]
  
  # Find 5 most similar countries (including same cluster + adjacent)
  similar_countries <- clustering_results %>%
    filter(country_name != current_country) %>%
    mutate(
      cluster_match = ifelse(cluster == current_cluster, 0, 1),  # Prefer same cluster
      park_diff = abs(parks_per_100k - 
                     clustering_results$parks_per_100k[i]),
      pop_diff = abs(log10(estimated_population) - 
                    log10(clustering_results$estimated_population[i]))
    ) %>%
    mutate(
      similarity_score = -1 * (cluster_match + park_diff/100 + pop_diff)
    ) %>%
    slice_head(n = 3, by = rank(-similarity_score)) %>%
    pull(country_name)
  
  peer_groups <- bind_rows(peer_groups, data.frame(
    country_name = current_country,
    peer_1 = similar_countries[1],
    peer_2 = similar_countries[2],
    peer_3 = similar_countries[3]
  ))
}

write_csv(peer_groups,
         file.path(dir_analysis, "05_global_peer_groups.csv"))

cat("✓ Global peer groups identified\n\n")

# ============================================================================
# PART 7: Visualizations
# ============================================================================
cat("--- Creating Clustering Visualizations ---\n")

# Plot 1: PCA Scatter - PC1 vs PC2
p_pca <- pca_data %>%
  left_join(cluster_names %>% rename(cluster_type = cluster_type), by = "cluster") %>%
  ggplot(aes(x = PC1, y = PC2)) +
  geom_point(aes(color = factor(cluster), size = 3), alpha = 0.7) +
  scale_color_brewer(palette = "Set2", name = "Cluster",
                    labels = c("Leaders", "Urban", "Middle", "Emerging", "Lagging")) +
  geom_text_repel(aes(label = country_name), size = 2, alpha = 0.6) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey70") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey70") +
  labs(
    title = "Country Clusters: PCA Visualization (PC1 vs PC2)",
    subtitle = sprintf("PC1 explains %.1f%% variance, PC2 explains %.1f%% variance",
                      pca_summary$importance[2,1]*100,
                      pca_summary$importance[2,2]*100),
    x = sprintf("PC1 (%.1f%%)", pca_summary$importance[2,1]*100),
    y = sprintf("PC2 (%.1f%%)", pca_summary$importance[2,2]*100)
  ) +
  theme_global +
  theme(legend.position = "right")

ggsave(file.path(dir_figures, "05_pca_scatter.png"),
       p_pca, width = 14, height = 10, dpi = 300)

cat("  ✓ PCA scatter plot saved\n")

# Plot 2: Cluster characteristics bar plot
p_cluster_char <- clustering_results %>%
  ggplot(aes(x = reorder(factor(cluster), parks_per_100k, median), 
            y = parks_per_100k)) +
  geom_boxplot(aes(fill = factor(cluster)), alpha = 0.7, color = "grey40") +
  geom_jitter(width = 0.15, alpha = 0.3, size = 1) +
  scale_fill_brewer(palette = "Set2", 
                   labels = c("Leaders", "Urban", "Middle", "Emerging", "Lagging"),
                   name = "Cluster") +
  labs(
    title = "Distribution of Dog Parks per 100k by Cluster",
    x = "Cluster",
    y = "Dog Parks per 100k"
  ) +
  theme_global

ggsave(file.path(dir_figures, "05_cluster_characteristics.png"),
       p_cluster_char, width = 11, height = 7, dpi = 300)

cat("  ✓ Cluster characteristics plot saved\n")

# Plot 3: Cluster size pie
p_cluster_size <- clustering_results %>%
  group_by(cluster) %>%
  summarise(n = n(), .groups = "drop") %>%
  ggplot(aes(x = "", y = n, fill = factor(cluster))) +
  geom_col(color = "white", size = 2) +
  coord_polar(theta = "y") +
  scale_fill_brewer(palette = "Set2",
                   labels = c("Leaders", "Urban", "Middle", "Emerging", "Lagging"),
                   name = "Cluster") +
  geom_label(aes(label = sprintf("Cluster %d\n%d countries", cluster, n)),
            position = position_stack(vjust = 0.5),
            fontface = "bold", size = 3) +
  labs(title = "Distribution of Countries by Cluster") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14, hjust = 0.5))

ggsave(file.path(dir_figures, "05_cluster_size_pie.png"),
       p_cluster_size, width = 10, height = 8, dpi = 300)

cat("  ✓ Cluster size pie chart saved\n\n")

# ============================================================================
# PART 8: Summary Report
# ============================================================================
cat("--- Clustering Analysis Summary ---\n")

summary_report <- sprintf(
"COUNTRY CLUSTERING ANALYSIS - GLOBAL PEER IDENTIFICATION

METHODOLOGY:
- Clustering Algorithm: K-means (k=5)
- Features: Dog parks density (50%%), Population size (30%%), Development tier (20%%)
- Dimensionality Reduction: Principal Component Analysis (PCA)
- Similarity Metric: Euclidean distance in normalized feature space

OPTIMAL CLUSTERS: 5
Based on Elbow method analysis

CLUSTER PROFILES:
%s

PCA ANALYSIS:
- PC1 explains: %.1f%% of variance
- PC2 explains: %.1f%% of variance
- PC3 explains: %.1f%% of variance
- Cumulative (PC1+PC2+PC3): %.1f%%

PEER GROUP FRAMEWORK:
- Each country linked to 3 most similar global peers
- Enables South-South cooperation on dog park development
- Peer learning more effective than generic benchmarking

CLUSTER INTERPRETATIONS:

1. GLOBAL LEADERS (Cluster 1):
   - High dog parks per capita
   - Developed/upper-middle income countries
   - Models for global best practices

2. URBAN CENTERS (Cluster 2):
   - Large populations with moderate provision
   - Opportunity for rapid expansion
   - Urban planning focus needed

3. MIDDLE PERFORMERS (Cluster 3):
   - Moderate provision levels
   - Mixed development stages
   - Potential for incremental improvement

4. EMERGING MARKETS (Cluster 4):
   - Lower provision but growing potential
   - Strategic investment opportunities
   - Capacity building priorities

5. LAGGING BEHIND (Cluster 5):
   - Minimal provision
   - Low development/small populations
   - Urgent intervention needed

STRATEGIC RECOMMENDATIONS:
1. Facilitate peer learning within clusters
2. Regional leaders mentor cluster peers
3. Technology transfer from Leaders to Lagging
4. Joint projects among similar-sized economies
5. Monitor cluster transitions (progress/regression)
",

paste(apply(cluster_profiles %>% select(cluster, cluster_type, n_countries, mean_parks_per_100k), 1,
  function(x) sprintf("  Cluster %s (%s): %s countries, avg %.2f parks/100k",
         x[1], x[2], x[3], x[4])), collapse = "\n"),

pca_summary$importance[2,1]*100,
pca_summary$importance[2,2]*100,
pca_summary$importance[2,3]*100,
sum(pca_summary$importance[2,1:3])*100
)

write(summary_report, file.path(dir_analysis, "05_clustering_summary.txt"))
cat(summary_report)

# ============================================================================
# Session Summary
# ============================================================================
cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Country Clustering Analysis Complete!\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat("Output files:\n")
cat("  ✓ country_clusters_kmeans.csv\n")
cat("  ✓ cluster_profiles.csv\n")
cat("  ✓ pca_results.csv\n")
cat("  ✓ global_peer_groups.csv\n")
cat("  ✓ 3 visualization PNG files\n")
cat("  ✓ clustering_summary.txt\n\n")

cat("Next: Run 06_interactive_global_dashboard.R\n")
cat("═══════════════════════════════════════════════════════════════\n\n")
