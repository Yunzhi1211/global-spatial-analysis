# ============================================================================
# 05_spatial_regression.R
# Spatial Regression Analysis
# ============================================================================
# Progression:
#   1. OLS Regression (baseline)
#   2. Diagnostic tests for spatial dependence
#   3. Spatial Lag Model (SLM)
#   4. Spatial Error Model (SEM)
#   5. Geographically Weighted Regression (GWR)
#   6. Model comparison and selection
# ============================================================================

source("00_setup.R")
load(file.path(dir_output, "accessibility_results.RData"))
load(file.path(dir_output, "spatial_autocorrelation_results.RData"))

# ============================================================================
# Research Questions for Regression:
# Q1: What factors explain green space per capita across districts?
# Q2: Is healthcare accessibility associated with green space availability?
# Q3: Do socio-economic factors moderate the green space - health relationship?
# ============================================================================

# Prepare data (drop geometry for OLS, keep for spatial models)
reg_data <- master %>%
  mutate(
    log_pop_density = log(pop_density),
    log_green_pc = log(green_area_per_capita + 1)
  )

# ============================================================================
# MODEL 1: OLS - Green Space Per Capita
# ============================================================================
cat("\n=== MODEL 1: OLS Regression ===\n")

# Dependent variable: green_area_per_capita
# Independent: pop_density, aging_ratio, public_housing_pct, degree_rate

ols_green <- lm(green_area_per_capita ~ log_pop_density + aging_ratio + 
                  public_housing_pct + degree_rate,
                data = reg_data)

summary(ols_green)

# Regression diagnostics
cat("\n--- OLS Diagnostics ---\n")
cat("AIC:", AIC(ols_green), "\n")
cat("BIC:", BIC(ols_green), "\n")

# Check residual normality
shapiro_test <- shapiro.test(residuals(ols_green))
cat("Shapiro-Wilk test p-value:", shapiro_test$p.value, "\n")

# Residual map
reg_data$ols_residuals <- residuals(ols_green)
reg_data$ols_fitted <- fitted(ols_green)

reg_wgs <- st_transform(reg_data, wgs84)

p_resid_ols <- ggplot(reg_wgs) +
  geom_sf(aes(fill = ols_residuals), color = "white", size = 0.5) +
  scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                        midpoint = 0, name = "OLS Residuals") +
  geom_sf_text(aes(label = name), size = 2.5) +
  labs(title = "OLS Residuals: Green Space Per Capita Model",
       subtitle = "Red = under-predicted, Blue = over-predicted") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "map_ols_residuals_green.png"), p_resid_ols,
       width = 12, height = 8, dpi = 300)

# ============================================================================
# MODEL 2: OLS - Healthcare Accessibility
# ============================================================================
cat("\n=== MODEL 2: OLS - Healthcare Accessibility ===\n")

if ("healthcare_access_2sfca" %in% names(reg_data)) {
  ols_health <- lm(healthcare_access_2sfca ~ green_area_per_capita + 
                     log_pop_density + aging_ratio + 
                     public_housing_pct,
                   data = reg_data)
  
  summary(ols_health)
  reg_data$ols_health_resid <- residuals(ols_health)
} else {
  cat("  SKIPPED: healthcare_access_2sfca not found.\n")
  cat("  Re-run 04_accessibility_analysis.R first.\n")
  ols_health <- NULL
}

# ============================================================================
# 3. Spatial Dependence Diagnostics
# ============================================================================
cat("\n=== Spatial Dependence Tests ===\n")

# Moran's I on OLS residuals
moran_resid <- lm.morantest(ols_green, lw_queen, zero.policy = TRUE)
cat("\nMoran's I on OLS residuals (Green Space model):\n")
print(moran_resid)

# Lagrange Multiplier tests
lm_tests <- lm.LMtests(ols_green, lw_queen,
                         test = c("LMerr", "LMlag", "RLMerr", "RLMlag", "SARMA"),
                         zero.policy = TRUE)
cat("\nLagrange Multiplier Tests:\n")
print(lm_tests)

# Interpretation guide
cat("\n--- Decision Rule ---\n")
cat("If LM-lag > LM-error AND RLM-lag significant => Spatial Lag Model\n")
cat("If LM-error > LM-lag AND RLM-error significant => Spatial Error Model\n")
cat("If both significant => Spatial Durbin Model or choose lower AIC\n")

# ============================================================================
# 4. Spatial Lag Model (SLM)
# ============================================================================
cat("\n=== Spatial Lag Model ===\n")

slm_green <- lagsarlm(green_area_per_capita ~ log_pop_density + aging_ratio +
                         public_housing_pct + degree_rate,
                       data = reg_data,
                       listw = lw_queen,
                       zero.policy = TRUE)

summary(slm_green)
cat("SLM AIC:", AIC(slm_green), "\n")

reg_data$slm_residuals <- residuals(slm_green)

# ============================================================================
# 5. Spatial Error Model (SEM)
# ============================================================================
cat("\n=== Spatial Error Model ===\n")

sem_green <- errorsarlm(green_area_per_capita ~ log_pop_density + aging_ratio +
                           public_housing_pct + degree_rate,
                         data = reg_data,
                         listw = lw_queen,
                         zero.policy = TRUE)

summary(sem_green)
cat("SEM AIC:", AIC(sem_green), "\n")

reg_data$sem_residuals <- residuals(sem_green)

# ============================================================================
# 6. Model Comparison: OLS vs SLM vs SEM
# ============================================================================
cat("\n=== Model Comparison ===\n")

comparison <- data.frame(
  Model = c("OLS", "Spatial Lag", "Spatial Error"),
  AIC = c(AIC(ols_green), AIC(slm_green), AIC(sem_green)),
  LogLik = c(logLik(ols_green), logLik(slm_green), logLik(sem_green))
)
comparison$Delta_AIC <- comparison$AIC - min(comparison$AIC)

print(comparison)
write_csv(comparison, file.path(dir_output, "model_comparison.csv"))

# Likelihood ratio tests
lr_slm <- anova(slm_green, ols_green)
lr_sem <- anova(sem_green, ols_green)
cat("\nLR test: SLM vs OLS\n")
print(lr_slm)
cat("\nLR test: SEM vs OLS\n")
print(lr_sem)

# ============================================================================
# 7. Geographically Weighted Regression (GWR)
# ============================================================================
cat("\n=== Geographically Weighted Regression ===\n")

# GWR requires Spatial objects (sp), not sf
# Cast to MULTIPOLYGON first to avoid sfc_GEOMETRY conversion error
reg_data_mp <- st_cast(reg_data, "MULTIPOLYGON")
reg_sp <- as(reg_data_mp, "Spatial")

# Optimal bandwidth selection using cross-validation
cat("Selecting optimal bandwidth (this may take a moment)...\n")
bw_gwr <- gwr.sel(green_area_per_capita ~ log_pop_density + aging_ratio +
                     public_housing_pct + degree_rate,
                   data = reg_sp,
                   adapt = TRUE,   # adaptive bandwidth (proportion of data)
                   gweight = gwr.Gauss)

cat("Optimal adaptive bandwidth:", bw_gwr, "\n")

# Fit GWR
gwr_model <- gwr(green_area_per_capita ~ log_pop_density + aging_ratio +
                    public_housing_pct + degree_rate,
                  data = reg_sp,
                  adapt = bw_gwr,
                  gweight = gwr.Gauss,
                  hatmatrix = TRUE,
                  se.fit = TRUE)

print(gwr_model)

# Extract GWR results
gwr_results <- as.data.frame(gwr_model$SDF)
gwr_sf <- st_as_sf(gwr_model$SDF) %>% st_set_crs(hk_crs)

# Add GWR coefficients to master
reg_data$gwr_intercept <- gwr_results$X.Intercept.
reg_data$gwr_pop_density <- gwr_results$log_pop_density
reg_data$gwr_aging <- gwr_results$aging_ratio
reg_data$gwr_housing <- gwr_results$public_housing_pct
reg_data$gwr_r2 <- gwr_results$localR2
reg_data$gwr_residuals <- gwr_model$SDF$gwr.e

cat("\n--- GWR Local R² Summary ---\n")
cat("Min:", min(reg_data$gwr_r2, na.rm = TRUE), "\n")
cat("Mean:", mean(reg_data$gwr_r2, na.rm = TRUE), "\n")
cat("Max:", max(reg_data$gwr_r2, na.rm = TRUE), "\n")

# ============================================================================
# 8. GWR Coefficient Maps
# ============================================================================
cat("\n--- Creating GWR Coefficient Maps ---\n")

reg_wgs <- st_transform(reg_data, wgs84)

# Local R²
p_gwr_r2 <- ggplot(reg_wgs) +
  geom_sf(aes(fill = gwr_r2), color = "white", size = 0.5) +
  scale_fill_viridis_c(option = "B", name = "Local R²") +
  geom_sf_text(aes(label = name), size = 2.5) +
  labs(title = "GWR Local R²",
       subtitle = "Model fit varies across districts") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "gwr_local_r2.png"), p_gwr_r2,
       width = 12, height = 8, dpi = 300)

# Population density coefficient
p_gwr_pop <- ggplot(reg_wgs) +
  geom_sf(aes(fill = gwr_pop_density), color = "white", size = 0.5) +
  scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                        midpoint = 0,
                        name = "Coefficient") +
  geom_sf_text(aes(label = name), size = 2.5) +
  labs(title = "GWR Coefficient: Log Population Density",
       subtitle = "Spatially varying effect on green space per capita") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "gwr_coeff_pop_density.png"), p_gwr_pop,
       width = 12, height = 8, dpi = 300)

# Aging ratio coefficient
p_gwr_aging <- ggplot(reg_wgs) +
  geom_sf(aes(fill = gwr_aging), color = "white", size = 0.5) +
  scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                        midpoint = 0,
                        name = "Coefficient") +
  geom_sf_text(aes(label = name), size = 2.5) +
  labs(title = "GWR Coefficient: Aging Ratio",
       subtitle = "Spatially varying effect on green space per capita") +
  theme_void() +
  theme(plot.title = element_text(face = "bold", size = 14))

ggsave(file.path(dir_figures, "gwr_coeff_aging.png"), p_gwr_aging,
       width = 12, height = 8, dpi = 300)

# Combined GWR coefficient panel
p_gwr_panel <- (p_gwr_r2 | p_gwr_pop) / (p_gwr_aging | p_gwr_pop)
ggsave(file.path(dir_figures, "gwr_panel.png"), p_gwr_panel,
       width = 16, height = 12, dpi = 300)

# ============================================================================
# 9. Residual Comparison Maps
# ============================================================================
cat("\n--- Comparing Residuals Across Models ---\n")

reg_wgs <- st_transform(reg_data, wgs84)

p_resid_compare <- ggplot(reg_wgs) +
  geom_sf(aes(fill = ols_residuals), color = "white") +
  scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                        midpoint = 0, name = "Residual") +
  labs(title = "OLS Residuals") +
  theme_void() -> p1

ggplot(reg_wgs) +
  geom_sf(aes(fill = slm_residuals), color = "white") +
  scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                        midpoint = 0, name = "Residual") +
  labs(title = "Spatial Lag Residuals") +
  theme_void() -> p2

ggplot(reg_wgs) +
  geom_sf(aes(fill = sem_residuals), color = "white") +
  scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                        midpoint = 0, name = "Residual") +
  labs(title = "Spatial Error Residuals") +
  theme_void() -> p3

ggplot(reg_wgs) +
  geom_sf(aes(fill = gwr_residuals), color = "white") +
  scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                        midpoint = 0, name = "Residual") +
  labs(title = "GWR Residuals") +
  theme_void() -> p4

p_all_resid <- (p1 | p2) / (p3 | p4) +
  plot_annotation(title = "Residual Comparison Across Spatial Regression Models",
                  theme = theme(plot.title = element_text(face = "bold", size = 16)))

ggsave(file.path(dir_figures, "residual_comparison_panel.png"), p_all_resid,
       width = 16, height = 12, dpi = 300)

# ============================================================================
# 10. Save All Results
# ============================================================================
save(ols_green, ols_health, slm_green, sem_green, gwr_model,
     reg_data, comparison,
     file = file.path(dir_output, "regression_results.RData"))

cat("\n=== Spatial Regression Analysis Complete! ===\n")
cat("Best model (lowest AIC):", comparison$Model[which.min(comparison$AIC)], "\n")
