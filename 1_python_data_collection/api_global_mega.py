#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Global Dog Parks Data - Query by Country Version (195 countries)
Data Source: OpenStreetMap + Overpass API

Academic Citation:
OpenStreetMap Foundation (2024). https://www.openstreetmap.org/
Overpass API: https://overpass-api.de/
Query tag: leisure=dog_park
"""

import requests
import json
import time
import pandas as pd
import pycountry

print("\n🐕 Global Dog Parks Data - Query by Country Version \n" + "="*70)

API_URL = "https://overpass.kumi.systems/api/interpreter"
BACKUP_URL = "https://z.overpass-api.de/api/interpreter"

# ============================================================================
# Get all ISO country codes + country name mapping
# ============================================================================

countries_list = []
country_names = {}

for country in pycountry.countries:
    countries_list.append(country.alpha_2)
    country_names[country.alpha_2] = country.name

print(f"📍 Retrieved {len(countries_list)} countries/regions (ISO standard)\n")

# ============================================================================
# Overpass query function - Query by country boundary
# ============================================================================

def build_query(iso_code):
    """Build Overpass query: Query dog parks by country administrative boundary"""
    return f"""
[out:json][timeout:90];
area["ISO3166-1"="{iso_code}"][admin_level=2]->.searchArea;
(
  node["leisure"="dog_park"](area.searchArea);
  way["leisure"="dog_park"](area.searchArea);
);
out center;
"""

# ============================================================================
# Main loop: Query all countries
# ============================================================================

all_parks = []
success_count = 0
failed_countries = []
retry_count = {}

for i, iso_code in enumerate(countries_list):
    country_name = country_names.get(iso_code, iso_code)
    display_name = f"{iso_code} ({country_name[:20]})"
    
    print(f"[{i+1:3d}/{len(countries_list)}] 🌍 {display_name:30s}", end=" ", flush=True)
    
    query = build_query(iso_code)
    
    # Retry mechanism
    max_retries = 2
    attempt = 0
    response = None
    
    while attempt <= max_retries:
        try:
            # Alternately use two Overpass mirrors
            url = API_URL if attempt % 2 == 0 else BACKUP_URL
            response = requests.post(url, data=query, timeout=90)
            
            if response.status_code == 200:
                break
            elif response.status_code == 429:
                print(f"⏳ Rate limit", end=" ", flush=True)
                time.sleep(30)
                attempt += 1
            elif response.status_code == 504:
                print(f"⏳ Server error", end=" ", flush=True)
                time.sleep(10)
                attempt += 1
            else:
                print(f"❌ {response.status_code}", end=" ", flush=True)
                break
                
        except requests.exceptions.Timeout:
            print(f"⏳ Timeout", end=" ", flush=True)
            attempt += 1
            time.sleep(5)
        except Exception as e:
            print(f"❌ Exception", end=" ", flush=True)
            attempt += 1
            time.sleep(5)
    
    # Handle response
    if response and response.status_code == 200:
        try:
            data = response.json()
            elements = data.get("elements", [])
            
            print(f"✅ {len(elements):4d} parks", flush=True)
            success_count += 1
            
            # Extract information for each park
            for elem in elements:
                try:
                    park_name = elem.get("tags", {}).get("name", f"Dog Park {elem['id']}")
                    
                    if elem["type"] == "node":
                        lat = elem["lat"]
                        lon = elem["lon"]
                    elif elem["type"] == "way" and "center" in elem:
                        lat = elem["center"]["lat"]
                        lon = elem["center"]["lon"]
                    else:
                        continue
                    
                    park = {
                        "name": park_name,
                        "latitude": lat,
                        "longitude": lon,
                        "country_code": iso_code,
                        "country_name": country_name,
                        "osm_id": elem["id"],
                        "osm_type": elem["type"],
                        "data_source": "OpenStreetMap"
                    }
                    all_parks.append(park)
                    
                except Exception as e:
                    continue
                    
        except json.JSONDecodeError:
            print(f"❌ JSON parsing error", flush=True)
            failed_countries.append(iso_code)
    else:
        print("❌ Failed", flush=True)
        failed_countries.append(iso_code)
    
    # Request interval - very important!
    time.sleep(1.5)


# ============================================================================
# Data processing and export
# ============================================================================

print(f"\n" + "="*70)
print(f"\n💾 Processing data...\n")

if all_parks:
    df = pd.DataFrame(all_parks)
    
    # Save CSV
    csv_file = "output/pet_parks_by_country.csv"
    df.to_csv(csv_file, index=False)
    print(f"✅ Saved CSV: {csv_file}")
    
    # Convert to GeoJSON
    features = []
    for _, row in df.iterrows():
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [row["longitude"], row["latitude"]]
            },
            "properties": {
                "name": row["name"],
                "country": row["country_name"],
                "country_code": row["country_code"],
                "osm_id": row["osm_id"],
                "osm_type": row["osm_type"]
            }
        }
        features.append(feature)
    
    geojson = {
        "type": "FeatureCollection",
        "properties": {
            "title": "Global Dog Parks Dataset",
            "description": f"Dog parks worldwide from {len(countries_list)} countries",
            "data_source": "OpenStreetMap contributors via Overpass API",
            "citation": "OpenStreetMap Foundation (2024). https://www.openstreetmap.org/",
            "api": "Overpass API https://overpass-api.de/",
            "query_method": "By country administrative boundaries",
            "query_tag": "leisure=dog_park",
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "total_parks": len(all_parks),
            "countries_queried": len(countries_list),
            "countries_with_results": df["country_code"].nunique(),
            "successful_queries": success_count,
        },
        "features": features
    }
    
    geojson_file = "output/pet_parks_by_country.geojson"
    with open(geojson_file, "w", encoding="utf-8") as f:
        json.dump(geojson, f, indent=2, ensure_ascii=False)
    print(f"✅ Saved GeoJSON: {geojson_file}")
    
    # ========== Detailed statistics ==========
    print(f"\n📊 Detailed Statistics:")
    print(f"  • Total parks: {len(all_parks):,}")
    print(f"  • Countries covered: {df['country_code'].nunique()}")
    print(f"  • Successful queries: {success_count}")
    print(f"  • Average per country: {len(all_parks) / df['country_code'].nunique():.1f} parks")
    
    print(f"\n🌍 Distribution by Country (TOP 30):")
    country_stats = df["country_name"].value_counts().head(30)
    for idx, (country, count) in enumerate(country_stats.items(), 1):
        bar_length = min(count // 5, 30)
        bar = "█" * bar_length
        print(f"  {idx:2d}. {country:25s}: {count:5d} parks  {bar}")
    
    print(f"\n🌎 Distribution by Continent:")
    # Simple continent classification
    continents = {
        "Europe": ["DE", "FR", "IT", "ES", "PL", "NL", "BE", "CH", "AT", "SE", "NO", "DK", 
                   "FI", "GB", "IE", "PT", "CZ", "HU", "RO", "BG", "HR", "SI", "SK", "GR"],
        "North America": ["US", "CA", "MX"],
        "South America": ["BR", "AR", "CL", "CO", "PE", "VE", "UY", "EC"],
        "Asia": ["CN", "JP", "KR", "IN", "TH", "VN", "ID", "MY", "SG", "PH", "TW", "HK", "KZ", "UZ"],
        "Africa": ["ZA", "EG", "NG", "KE", "ET", "GH", "MA", "TN"],
        "Oceania": ["AU", "NZ"],
    }
    
    for continent, codes in continents.items():
        count = len(df[df["country_code"].isin(codes)])
        if count > 0:
            print(f"  • {continent:20s}: {count:5d} parks")
    
    # ========== Failed countries list ==========
    if failed_countries:
        print(f"\n⚠️ Countries with failed queries ({len(failed_countries)}):")
        for iso in failed_countries[:20]:
            print(f"  • {iso} ({country_names.get(iso, 'Unknown')})")
        if len(failed_countries) > 20:
            print(f"  ... and {len(failed_countries) - 20} more")
    
    print(f"\n" + "="*70)
    print(f"\n✅ Complete!")
    print(f"\n📝 Academic Citation:")
    print(f"   Data source: OpenStreetMap contributors")
    print(f"   URL: https://www.openstreetmap.org/")
    print(f"   API: Overpass API (https://overpass-api.de/)")
    print(f"   Query: leisure=dog_park within administrative boundaries of {len(countries_list)} countries")
    print(f"   Timestamp: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    
else:
    print("❌ No data found")

