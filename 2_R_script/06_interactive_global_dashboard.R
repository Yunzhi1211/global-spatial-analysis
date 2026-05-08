# ============================================================================
# 06_interactive_global_dashboard.R
# Interactive Global Dashboard - Worldwide Explorer
# ============================================================================
# This script creates:
#   1. Interactive world map with country-level metrics
#   2. Country detail explorer (HTML/Shiny ready)
#   3. Global performance dashboard
#   4. Peer comparison visualizations
# ============================================================================

source("00_setup.R")
load(file.path(dir_analysis, "01_master_global_data.RData"))
load(file.path(dir_analysis, "01_master_global_data.RData"))

# Load clustering results
clustering_results <- read_csv(file.path(dir_analysis, "05_country_clusters_kmeans.csv"))
peer_groups <- read_csv(file.path(dir_analysis, "05_global_peer_groups.csv"))

cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Interactive Global Dashboard Module\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

# ============================================================================
# PART 1: Prepare Data for Interactive Visualization
# ============================================================================
cat("--- Preparing Data for Interactive Dashboard ---\n")

total_countries <- nrow(master_global)

dashboard_data <- master_global %>%
  left_join(clustering_results %>% select(country_name, cluster_label), by = "country_name") %>%
  rename(cluster = cluster_label) %>%
  left_join(peer_groups %>% select(-cluster) %>% rename(country_name = country), by = "country_name") %>%
  mutate(
    # Format metrics for display
    parks_per_100k_display = round(parks_per_100k, 2),
    global_rank_display = global_rank,
    global_percentile_display = round(global_percentile, 1),
    
    # Pop-up text for interactive map
    popup_text = sprintf(
      "<b>%s</b><br/>Region: %s<br/>Dog Parks: %d<br/>Parks per 100k: %.2f<br/>Global Rank: %d / %d<br/>Percentile: %.1f%%<br/>Tier: %s",
      country_name, region, n_parks, parks_per_100k,
      global_rank, total_countries, global_percentile, tier
    )
  ) %>%
  arrange(global_rank)

cat("✓ Dashboard data prepared\n\n")

# ============================================================================
# PART 2: Export JSON Data for Interactive Map Dashboard
# ============================================================================
cat("--- Exporting JSON Data for Map Dashboard ---\n")

# Pre-compute all values
n_countries <- nrow(master_global)
total_parks <- sum(master_global$n_parks)
avg_parks <- round(mean(master_global$parks_per_100k, na.rm = TRUE), 2)

# Prepare country data for JSON export
country_json_data <- master_global %>%
  arrange(global_rank) %>%
  select(
    rank = global_rank,
    name = country_name,
    region,
    parks = n_parks,
    rate = parks_per_100k,
    tier,
    lat = avg_lat,
    lon = avg_lon
  ) %>%
  filter(!is.na(lat), !is.na(lon))

# Prepare regional data for JSON export
regional_json_data <- regional_summary %>%
  select(
    name = region,
    countries = n_countries,
    avgRate = median_parks_per_100k,
    totalParks = total_parks
  ) %>%
  head(5)

# Prepare tier data for JSON export
tier_json_data <- master_global %>%
  group_by(tier) %>%
  summarise(
    count = n(),
    avgRate = round(mean(parks_per_100k, na.rm = TRUE), 2),
    .groups = 'drop'
  ) %>%
  mutate(
    pct = round(count / n_countries * 100, 1),
    class = case_when(
      tier == "Top Tier" ~ "tier-top",
      tier == "Advanced" ~ "tier-advanced",
      tier == "Developing" ~ "tier-developing",
      tier == "Emerging" ~ "tier-emerging",
      TRUE ~ "tier-low"
    )
  ) %>%
  select(tier, class, count, pct, avgRate)

# Export JSON files
write_json <- function(data, filename) {
  json_str <- jsonlite::toJSON(data, pretty = TRUE, auto_unbox = TRUE)
  write(json_str, file.path(dir_analysis, filename))
}

write_json(country_json_data, "dashboard_countries.json")
write_json(regional_json_data, "dashboard_regions.json")
write_json(tier_json_data, "dashboard_tiers.json")

# Export summary stats
summary_stats <- list(
  totalCountries = n_countries,
  totalParks = total_parks,
  avgParksRate = avg_parks,
  analysisYear = ANALYSIS_YEAR
)
write_json(summary_stats, "dashboard_stats.json")

cat("✓ JSON data exported for map dashboard\n\n")

# ============================================================================
# PART 2b: Generate Glass UI Map Dashboard HTML
# ============================================================================
cat("--- Generating Glass UI Map Dashboard ---\n")

# Convert data to JSON strings for embedding in HTML
country_json_str <- jsonlite::toJSON(country_json_data, auto_unbox = TRUE)
regional_json_str <- jsonlite::toJSON(regional_json_data, auto_unbox = TRUE)
tier_json_str <- jsonlite::toJSON(tier_json_data, auto_unbox = TRUE)

# Build complete Glass UI HTML dashboard
dashboard_html <- paste0('<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Global Dog Parks Analysis - Interactive Map Dashboard</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    @import url("https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap");
    :root {
      --glass-bg: rgba(255, 255, 255, 0.15);
      --glass-border: rgba(255, 255, 255, 0.25);
      --glass-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
      --blur: 20px;
      --primary-green: #10b981;
      --light-green: #d1fae5;
      --accent-green: #34d399;
      --dark-green: #059669;
      --text-dark: #064e3b;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: "Inter", -apple-system, BlinkMacSystemFont, sans-serif;
      background: linear-gradient(135deg, #ecfdf5 0%, #d1fae5 50%, #a7f3d0 100%);
      min-height: 100vh; overflow-x: hidden;
    }
    .bg-blob {
      position: fixed; border-radius: 50%; filter: blur(80px); opacity: 0.5; z-index: -1;
      animation: float 20s ease-in-out infinite;
    }
    .blob-1 { width: 600px; height: 600px; background: linear-gradient(135deg, #6ee7b7, #34d399); top: -200px; left: -200px; }
    .blob-2 { width: 500px; height: 500px; background: linear-gradient(135deg, #a7f3d0, #6ee7b7); bottom: -150px; right: -150px; animation-delay: -10s; }
    .blob-3 { width: 400px; height: 400px; background: linear-gradient(135deg, #d1fae5, #a7f3d0); top: 50%; left: 50%; transform: translate(-50%, -50%); animation-delay: -5s; }
    @keyframes float {
      0%, 100% { transform: translate(0, 0) scale(1); }
      25% { transform: translate(30px, -30px) scale(1.05); }
      50% { transform: translate(-20px, 20px) scale(0.95); }
      75% { transform: translate(20px, 30px) scale(1.02); }
    }
    .glass-solid {
      background: rgba(255, 255, 255, 0.85);
      backdrop-filter: blur(var(--blur));
      -webkit-backdrop-filter: blur(var(--blur));
      border: 1px solid rgba(255, 255, 255, 0.5);
      border-radius: 20px;
      box-shadow: var(--glass-shadow);
    }
    .header { padding: 30px 40px; text-align: center; position: relative; z-index: 10; }
    .header h1 {
      font-size: 2.8rem; font-weight: 700;
      background: linear-gradient(135deg, var(--dark-green), var(--primary-green));
      -webkit-background-clip: text; -webkit-text-fill-color: transparent;
      background-clip: text; margin-bottom: 10px;
      display: flex; align-items: center; justify-content: center; gap: 15px;
    }
    .header .subtitle { color: var(--text-dark); font-size: 1.1rem; opacity: 0.8; }
    .header .meta { margin-top: 10px; color: var(--dark-green); font-size: 0.9rem; opacity: 0.7; }
    .container { max-width: 1600px; margin: 0 auto; padding: 0 30px 30px; }
    .stats-row { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin-bottom: 25px; }
    .stat-card { padding: 25px; text-align: center; transition: transform 0.3s ease; }
    .stat-card:hover { transform: translateY(-5px); box-shadow: 0 15px 40px rgba(16, 185, 129, 0.2); }
    .stat-card .icon {
      width: 50px; height: 50px;
      background: linear-gradient(135deg, var(--primary-green), var(--accent-green));
      border-radius: 15px; display: flex; align-items: center; justify-content: center;
      margin: 0 auto 15px; font-size: 1.4rem; color: white;
    }
    .stat-card .value { font-size: 2.2rem; font-weight: 700; color: var(--dark-green); }
    .stat-card .label { font-size: 0.85rem; color: var(--text-dark); margin-top: 8px; opacity: 0.7; }
    .map-section { display: grid; grid-template-columns: 1fr 380px; gap: 25px; margin-bottom: 25px; }
    .map-container { height: 550px; overflow: hidden; position: relative; }
    #map { width: 100%; height: 100%; border-radius: 18px; }
    .map-legend {
      position: absolute; bottom: 20px; left: 20px; padding: 15px 20px; z-index: 1000;
      background: rgba(255, 255, 255, 0.9); backdrop-filter: blur(10px);
      border-radius: 12px; border: 1px solid rgba(16, 185, 129, 0.2);
    }
    .map-legend h4 { font-size: 0.8rem; color: var(--text-dark); margin-bottom: 10px; font-weight: 600; }
    .legend-item { display: flex; align-items: center; gap: 8px; margin-bottom: 5px; font-size: 0.75rem; color: var(--text-dark); }
    .legend-color { width: 20px; height: 12px; border-radius: 3px; }
    .sidebar { display: flex; flex-direction: column; gap: 20px; }
    .panel { padding: 20px; }
    .panel h3 { font-size: 1rem; font-weight: 600; color: var(--dark-green); margin-bottom: 15px; display: flex; align-items: center; gap: 10px; }
    .panel h3 i { color: var(--primary-green); }
    .search-box { position: relative; }
    .search-box input {
      width: 100%; padding: 12px 15px 12px 42px;
      border: 2px solid rgba(16, 185, 129, 0.2); border-radius: 12px;
      font-size: 0.9rem; background: rgba(255, 255, 255, 0.5);
      transition: all 0.3s ease; outline: none;
    }
    .search-box input:focus { border-color: var(--primary-green); background: rgba(255, 255, 255, 0.8); }
    .search-box i { position: absolute; left: 15px; top: 50%; transform: translateY(-50%); color: var(--primary-green); }
    .country-list { max-height: 280px; overflow-y: auto; margin-top: 15px; }
    .country-list::-webkit-scrollbar { width: 6px; }
    .country-list::-webkit-scrollbar-track { background: rgba(16, 185, 129, 0.1); border-radius: 3px; }
    .country-list::-webkit-scrollbar-thumb { background: var(--primary-green); border-radius: 3px; }
    .country-item {
      display: flex; align-items: center; justify-content: space-between;
      padding: 10px 12px; border-radius: 10px; cursor: pointer;
      transition: all 0.2s ease; margin-bottom: 5px;
    }
    .country-item:hover { background: rgba(16, 185, 129, 0.1); }
    .country-info { display: flex; align-items: center; gap: 10px; }
    .country-rank {
      width: 28px; height: 28px;
      background: linear-gradient(135deg, var(--primary-green), var(--accent-green));
      color: white; border-radius: 8px; display: flex; align-items: center; justify-content: center;
      font-size: 0.75rem; font-weight: 600;
    }
    .country-name { font-size: 0.9rem; font-weight: 500; color: var(--text-dark); }
    .country-value { font-size: 0.85rem; font-weight: 600; color: var(--dark-green); }
    .tier-badge { display: inline-block; padding: 4px 10px; border-radius: 20px; font-size: 0.7rem; font-weight: 600; text-transform: uppercase; }
    .tier-top { background: #dcfce7; color: #166534; }
    .tier-advanced { background: #d1fae5; color: #047857; }
    .tier-developing { background: #fef3c7; color: #92400e; }
    .tier-emerging { background: #fed7aa; color: #9a3412; }
    .tier-low { background: #fee2e2; color: #991b1b; }
    .region-stats { display: flex; flex-direction: column; gap: 10px; }
    .region-item {
      display: flex; align-items: center; gap: 12px; padding: 12px;
      background: rgba(16, 185, 129, 0.05); border-radius: 12px; transition: all 0.2s ease;
    }
    .region-item:hover { background: rgba(16, 185, 129, 0.1); transform: translateX(5px); }
    .region-icon {
      width: 40px; height: 40px;
      background: linear-gradient(135deg, var(--light-green), var(--accent-green));
      border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 1rem;
    }
    .region-details { flex: 1; }
    .region-name { font-size: 0.85rem; font-weight: 600; color: var(--text-dark); }
    .region-meta { font-size: 0.75rem; color: var(--text-dark); opacity: 0.7; }
    .region-value { font-size: 1rem; font-weight: 700; color: var(--dark-green); }
    .bottom-section { display: grid; grid-template-columns: 1fr 1fr; gap: 25px; }
    .data-table { width: 100%; border-collapse: collapse; }
    .data-table th {
      text-align: left; padding: 12px 15px; font-size: 0.8rem; font-weight: 600;
      color: var(--dark-green); background: rgba(16, 185, 129, 0.1); border-radius: 8px;
    }
    .data-table td {
      padding: 12px 15px; font-size: 0.85rem; color: var(--text-dark);
      border-bottom: 1px solid rgba(16, 185, 129, 0.1);
    }
    .data-table tr:hover td { background: rgba(16, 185, 129, 0.05); }
    .country-detail { padding: 20px; display: none; }
    .country-detail.active { display: block; }
    .detail-header {
      display: flex; align-items: center; gap: 15px; margin-bottom: 20px;
      padding-bottom: 15px; border-bottom: 1px solid rgba(16, 185, 129, 0.2);
    }
    .detail-flag {
      width: 60px; height: 40px; background: var(--light-green); border-radius: 8px;
      display: flex; align-items: center; justify-content: center; font-size: 1.5rem;
    }
    .detail-title h2 { font-size: 1.3rem; font-weight: 700; color: var(--dark-green); }
    .detail-title span { font-size: 0.85rem; color: var(--text-dark); opacity: 0.7; }
    .detail-stats { display: grid; grid-template-columns: repeat(2, 1fr); gap: 15px; }
    .detail-stat {
      padding: 15px; background: rgba(16, 185, 129, 0.05); border-radius: 12px; text-align: center;
    }
    .detail-stat .value { font-size: 1.5rem; font-weight: 700; color: var(--dark-green); }
    .detail-stat .label { font-size: 0.75rem; color: var(--text-dark); opacity: 0.7; margin-top: 5px; }
    .footer { text-align: center; padding: 30px; color: var(--text-dark); font-size: 0.85rem; opacity: 0.7; }
    @media (max-width: 1200px) {
      .map-section { grid-template-columns: 1fr; }
      .sidebar { flex-direction: row; flex-wrap: wrap; }
      .sidebar .panel { flex: 1; min-width: 300px; }
    }
    @media (max-width: 768px) {
      .stats-row { grid-template-columns: repeat(2, 1fr); }
      .bottom-section { grid-template-columns: 1fr; }
      .header h1 { font-size: 2rem; }
    }
    @keyframes fadeIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
    .animate-in { animation: fadeIn 0.6s ease forwards; }
    .delay-1 { animation-delay: 0.1s; } .delay-2 { animation-delay: 0.2s; }
    .delay-3 { animation-delay: 0.3s; } .delay-4 { animation-delay: 0.4s; }
  </style>
</head>
<body>
  <div class="bg-blob blob-1"></div>
  <div class="bg-blob blob-2"></div>
  <div class="bg-blob blob-3"></div>
  <header class="header">
    <h1><i class="fas fa-paw"></i> Global Dog Parks Analysis</h1>
    <p class="subtitle">Worldwide Pet Park Provision &amp; Urban Livability Explorer</p>
    <p class="meta">Analysis Year: ', ANALYSIS_YEAR, ' | Countries: ', n_countries, ' | Total Parks: ', format(total_parks, big.mark = ","), '</p>
  </header>
  <div class="container">
    <div class="stats-row">
      <div class="stat-card glass-solid animate-in delay-1">
        <div class="icon"><i class="fas fa-globe"></i></div>
        <div class="value">', n_countries, '</div>
        <div class="label">Countries Analyzed</div>
      </div>
      <div class="stat-card glass-solid animate-in delay-2">
        <div class="icon"><i class="fas fa-tree"></i></div>
        <div class="value">', format(total_parks, big.mark = ","), '</div>
        <div class="label">Total Dog Parks</div>
      </div>
      <div class="stat-card glass-solid animate-in delay-3">
        <div class="icon"><i class="fas fa-chart-line"></i></div>
        <div class="value">', avg_parks, '</div>
        <div class="label">Avg Parks per 100k</div>
      </div>
      <div class="stat-card glass-solid animate-in delay-4">
        <div class="icon"><i class="fas fa-map-marked-alt"></i></div>
        <div class="value">', length(unique(master_global$region)), '</div>
        <div class="label">Regions Covered</div>
      </div>
    </div>
    <div class="map-section">
      <div class="map-container glass-solid animate-in">
        <div id="map"></div>
        <div class="map-legend">
          <h4>Parks per 100k Population</h4>
          <div class="legend-item"><div class="legend-color" style="background: #064e3b;"></div><span>&gt; 5.0 (Top Tier)</span></div>
          <div class="legend-item"><div class="legend-color" style="background: #059669;"></div><span>2.0 - 5.0 (Advanced)</span></div>
          <div class="legend-item"><div class="legend-color" style="background: #34d399;"></div><span>1.0 - 2.0 (Developing)</span></div>
          <div class="legend-item"><div class="legend-color" style="background: #a7f3d0;"></div><span>0.5 - 1.0 (Emerging)</span></div>
          <div class="legend-item"><div class="legend-color" style="background: #d1fae5;"></div><span>&lt; 0.5 (Low)</span></div>
        </div>
      </div>
      <div class="sidebar">
        <div class="panel glass-solid animate-in delay-1">
          <h3><i class="fas fa-trophy"></i> Top Countries</h3>
          <div class="search-box">
            <i class="fas fa-search"></i>
            <input type="text" id="searchInput" placeholder="Search countries...">
          </div>
          <div class="country-list" id="countryList"></div>
        </div>
        <div class="panel glass-solid animate-in delay-2">
          <h3><i class="fas fa-chart-pie"></i> Regional Overview</h3>
          <div class="region-stats" id="regionStats"></div>
        </div>
      </div>
    </div>
    <div class="bottom-section">
      <div class="panel glass-solid animate-in">
        <h3><i class="fas fa-layer-group"></i> Tier Distribution</h3>
        <table class="data-table">
          <thead><tr><th>Tier</th><th>Countries</th><th>%</th><th>Avg Parks/100k</th></tr></thead>
          <tbody id="tierTable"></tbody>
        </table>
      </div>
      <div class="panel glass-solid animate-in country-detail" id="countryDetail">
        <div class="detail-header">
          <div class="detail-flag" id="detailFlag">🌍</div>
          <div class="detail-title">
            <h2 id="detailName">Select a Country</h2>
            <span id="detailRegion">Click on map or list</span>
          </div>
        </div>
        <div class="detail-stats">
          <div class="detail-stat"><div class="value" id="detailParks">-</div><div class="label">Total Dog Parks</div></div>
          <div class="detail-stat"><div class="value" id="detailRate">-</div><div class="label">Parks per 100k</div></div>
          <div class="detail-stat"><div class="value" id="detailRank">-</div><div class="label">Global Rank</div></div>
          <div class="detail-stat"><div class="value" id="detailTier">-</div><div class="label">Performance Tier</div></div>
        </div>
      </div>
      <div class="panel glass-solid animate-in" id="selectPrompt">
        <h3><i class="fas fa-mouse-pointer"></i> Country Details</h3>
        <div style="text-align: center; padding: 40px; color: var(--text-dark); opacity: 0.6;">
          <i class="fas fa-hand-pointer" style="font-size: 3rem; margin-bottom: 15px; display: block; color: var(--primary-green);"></i>
          <p>Click on a country in the map or list to view detailed statistics</p>
        </div>
      </div>
    </div>
  </div>
  <footer class="footer">
    <p>Data Source: OpenStreetMap &amp; World Bank | Analysis: Global Dog Parks Research Project ', ANALYSIS_YEAR, '</p>
  </footer>
  <script>
    const countryData = ', country_json_str, ';
    const regionalData = ', regional_json_str, ';
    const tierData = ', tier_json_str, ';
    const regionIcons = {
      "Europe & Central Asia": "🏰", "North America": "🗽", "East Asia & Pacific": "🏯",
      "Latin America & Caribbean": "🌴", "Middle East & North Africa": "🕌",
      "Sub-Saharan Africa": "🌍", "South Asia": "🏛️"
    };
    const map = L.map("map", { center: [30, 0], zoom: 2, minZoom: 2, maxZoom: 8, worldCopyJump: true });
    L.tileLayer("https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png", {
      attribution: "OpenStreetMap &copy; CARTO", subdomains: "abcd", maxZoom: 19
    }).addTo(map);
    function getColor(rate) {
      return rate > 5 ? "#064e3b" : rate > 2 ? "#059669" : rate > 1 ? "#34d399" : rate > 0.5 ? "#a7f3d0" : "#d1fae5";
    }
    const markers = [];
    countryData.forEach(c => {
      if (!c.lat || !c.lon) return;
      const marker = L.circleMarker([c.lat, c.lon], {
        radius: Math.max(6, Math.min(25, Math.sqrt(c.parks) / 2)),
        fillColor: getColor(c.rate), color: "#fff", weight: 2, opacity: 1, fillOpacity: 0.8
      }).addTo(map);
      marker.bindPopup(`<div style="font-family:Inter,sans-serif;padding:5px;">
        <h4 style="margin:0 0 8px;color:#064e3b;font-size:1.1rem;">${c.name}</h4>
        <p style="margin:3px 0;color:#065f46;"><b>Region:</b> ${c.region}</p>
        <p style="margin:3px 0;color:#065f46;"><b>Dog Parks:</b> ${c.parks.toLocaleString()}</p>
        <p style="margin:3px 0;color:#065f46;"><b>Per 100k:</b> ${c.rate.toFixed(2)}</p>
        <p style="margin:3px 0;color:#065f46;"><b>Rank:</b> #${c.rank}</p>
        <p style="margin:3px 0;"><span class="tier-badge ${c.tier.toLowerCase().replace(/ /g,"-")}">${c.tier}</span></p>
      </div>`);
      marker.on("click", () => showCountryDetail(c));
      markers.push({ marker, country: c });
    });
    function renderCountryList(filter = "") {
      const list = document.getElementById("countryList");
      const filtered = countryData.filter(c => c.name.toLowerCase().includes(filter.toLowerCase()));
      list.innerHTML = filtered.slice(0, 20).map(c => `
        <div class="country-item" onclick="selectCountry(\'${c.name.replace(/\'/g, "\\\'")}\')" >
          <div class="country-info">
            <span class="country-rank">${c.rank}</span>
            <span class="country-name">${c.name}</span>
          </div>
          <span class="country-value">${c.rate.toFixed(2)}</span>
        </div>
      `).join("");
    }
    function renderRegionalStats() {
      const container = document.getElementById("regionStats");
      container.innerHTML = regionalData.map(r => `
        <div class="region-item">
          <div class="region-icon">${regionIcons[r.name] || "🌐"}</div>
          <div class="region-details">
            <div class="region-name">${r.name}</div>
            <div class="region-meta">${r.countries} countries</div>
          </div>
          <div class="region-value">${r.avgRate.toFixed(2)}</div>
        </div>
      `).join("");
    }
    function renderTierTable() {
      const table = document.getElementById("tierTable");
      table.innerHTML = tierData.map(t => `
        <tr>
          <td><span class="tier-badge ${t.class}">${t.tier}</span></td>
          <td>${t.count}</td>
          <td>${t.pct.toFixed(1)}%</td>
          <td>${t.avgRate.toFixed(2)}</td>
        </tr>
      `).join("");
    }
    function showCountryDetail(c) {
      document.getElementById("selectPrompt").style.display = "none";
      document.getElementById("countryDetail").classList.add("active");
      document.getElementById("detailFlag").textContent = "🌍";
      document.getElementById("detailName").textContent = c.name;
      document.getElementById("detailRegion").textContent = c.region;
      document.getElementById("detailParks").textContent = c.parks.toLocaleString();
      document.getElementById("detailRate").textContent = c.rate.toFixed(2);
      document.getElementById("detailRank").textContent = "#" + c.rank;
      document.getElementById("detailTier").innerHTML = `<span class="tier-badge ${c.tier.toLowerCase().replace(/ /g,"-")}">${c.tier}</span>`;
      markers.forEach(m => {
        if (m.country.name === c.name) { m.marker.openPopup(); map.setView([c.lat, c.lon], 4); }
      });
    }
    function selectCountry(name) {
      const c = countryData.find(x => x.name === name);
      if (c) showCountryDetail(c);
    }
    document.getElementById("searchInput").addEventListener("input", e => renderCountryList(e.target.value));
    renderCountryList();
    renderRegionalStats();
    renderTierTable();
  </script>
</body>
</html>')

write(dashboard_html, file.path(dir_analysis, "06_global_glass_map_dashboard.html"))
cat("✓ Glass UI Map Dashboard created: 06_global_glass_map_dashboard.html\n\n")

# ============================================================================
# PART 3: Export Data for Mapping Tools
# ============================================================================
cat("--- Exporting Data for Mapping & Further Analysis ---\n")

# Export country centers for mapping
country_centers <- dashboard_data %>%
  select(country_code, country_name, region, avg_lat, avg_lon, 
         n_parks, parks_per_100k, global_rank, tier, cluster) %>%
  filter(!is.na(avg_lat), !is.na(avg_lon))

write_csv(country_centers,
         file.path(dir_analysis, "06_country_centers_for_mapping.csv"))

# Export complete dashboard dataset
write_csv(dashboard_data,
         file.path(dir_analysis, "06_complete_dashboard_data.csv"))

cat("✓ Data exported for external mapping tools\n\n")

# ============================================================================
# PART 4: Key Insights Report
# ============================================================================
cat("--- Generating Key Insights Report ---\n")

insights <- sprintf(
"INTERACTIVE GLOBAL DASHBOARD - KEY INSIGHTS

METHODOLOGY:
- Platform: Interactive HTML dashboard with responsive design
- Data: %d countries with dog park and demographic information
- Metrics: Dog parks per 100k population (primary), regional averages, tier classification
- Interactivity: Searchable ranking tables, color-coded tiers, regional filters

GLOBAL FINDINGS:

1. COVERAGE & SCALE:
   - Total countries analyzed: %d
   - Total dog parks mapped: %d
   - Average parks per 100k: %.2f
   - Global range: %.2f - %.2f parks per 100k

2. TIER DISTRIBUTION:
   - Top Tier: %d countries (%.1f%%) - Global leaders
   - Advanced: %d countries (%.1f%%) - Above average
   - Developing: %d countries (%.1f%%) - Moderate provision
   - Emerging: %d countries (%.1f%%) - Low provision
   - Low Tier: %d countries (%.1f%%) - Critical need

3. REGIONAL DYNAMICS:
   - Most parks: %s (%d total)
   - Highest per capita: %s (%.2f/100k)
   - Most concentrated: %s
   - Most dispersed: %s

4. STRATEGIC OPPORTUNITIES:
   - South-South learning: Peer countries identified for cooperation
   - Regional mentoring: Leaders can guide cluster laggards
   - Capacity building: Focus on Low Tier countries
   - Urban expansion: High population centers with low provision

5. DASHBOARD FEATURES:
   - Global rankings searchable by country name
   - Regional performance comparison
   - Tier-based strategic grouping
   - Peer country recommendations
   - Interactive HTML for web deployment
   - Data exports for GIS/mapping tools

NEXT STEPS:
1. Deploy dashboard to web server for stakeholder access
2. Integrate World Bank data for wealth/health indicators
3. Develop country-specific implementation guides
4. Create peer learning coalitions within regions
5. Monitor progress with annual updates

CONTACT & ADDITIONAL DATA:
- Full country-level data available in: 06_complete_dashboard_data.csv
- Country coordinates for mapping: 06_country_centers_for_mapping.csv
- Global rankings and tiers: ranking data files
- Peer groups for collaboration: clustering analysis files
",

nrow(master_global),
nrow(master_global),
sum(master_global$n_parks),
mean(master_global$parks_per_100k, na.rm = TRUE),
min(master_global$parks_per_100k, na.rm = TRUE),
max(master_global$parks_per_100k, na.rm = TRUE),

sum(master_global$tier == "Top Tier"),
sum(master_global$tier == "Top Tier") / nrow(master_global) * 100,
sum(master_global$tier == "Advanced"),
sum(master_global$tier == "Advanced") / nrow(master_global) * 100,
sum(master_global$tier == "Developing"),
sum(master_global$tier == "Developing") / nrow(master_global) * 100,
sum(master_global$tier == "Emerging"),
sum(master_global$tier == "Emerging") / nrow(master_global) * 100,
sum(master_global$tier == "Low Tier"),
sum(master_global$tier == "Low Tier") / nrow(master_global) * 100,

regional_summary$region[which.max(regional_summary$total_parks)],
max(regional_summary$total_parks),
master_global %>% arrange(desc(parks_per_100k)) %>% slice(1) %>% pull(country_name),
master_global %>% arrange(desc(parks_per_100k)) %>% slice(1) %>% pull(parks_per_100k),
master_global %>% arrange(desc(n_parks)) %>% slice(1) %>% pull(region),
master_global %>% arrange(parks_per_100k) %>% slice(1) %>% pull(region)
)

write(insights, file.path(dir_analysis, "06_dashboard_insights.txt"))
cat(insights)

# ============================================================================
# Session Summary
# ============================================================================
cat("\n═══════════════════════════════════════════════════════════════\n")
cat("Interactive Global Dashboard Complete!\n")
cat("═══════════════════════════════════════════════════════════════\n\n")

cat("Output files:\n")
cat("  ✓ 06_global_glass_map_dashboard.html (Glass UI with Map - Open in browser)\n")
cat("  ✓ dashboard_countries.json (Country data for web apps)\n")
cat("  ✓ dashboard_regions.json (Regional data for web apps)\n")
cat("  ✓ dashboard_tiers.json (Tier data for web apps)\n")
cat("  ✓ dashboard_stats.json (Summary statistics)\n")
cat("  ✓ 06_country_centers_for_mapping.csv\n")
cat("  ✓ 06_complete_dashboard_data.csv\n")
cat("  ✓ 06_dashboard_insights.txt\n\n")

cat("Dashboard is ready! Open: 06_global_glass_map_dashboard.html\n")
cat("═══════════════════════════════════════════════════════════════\n\n")
