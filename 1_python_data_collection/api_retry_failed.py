#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Re-query failed countries + performance comparison (node vs way)
Special focus: US, China and other key countries
"""

import requests
import json
import time
import pandas as pd
import pycountry

print("\n🔄 Re-query failed countries + performance comparison\n" + "="*70)

API_URL = "https://overpass.kumi.systems/api/interpreter"

# First check existing data
existing_df = pd.read_csv("output/pet_parks_by_country.csv")
existing_countries = set(existing_df['country_code'].unique())

print(f"📊 Existing data statistics:")
print(f"  • Total records: {len(existing_df):,}")
print(f"  • Countries covered: {len(existing_countries)}")
print(f"  • Node type: {len(existing_df[existing_df['osm_type']=='node']):,}")
print(f"  • Way type: {len(existing_df[existing_df['osm_type']=='way']):,}")

# Check key countries for data
key_countries = {"GB": "United Kingdom", "HK": "Hong Kong", "US": "United States", "CN": "China", "JP": "Japan", "DE": "Germany", "FR": "France", "IN": "India"}
print(f"\n🔎 Key countries data (User focus: GB UK, HK Hong Kong):")
for code, name in key_countries.items():
    count = len(existing_df[existing_df['country_code'] == code])
    status = "✅" if count > 0 else "❌"
    priority_flag = "🔴" if code in ["GB", "HK"] else "  "
    print(f"  {priority_flag} {status} {code} ({name}): {count} parks")

# ============================================================================
# Get all countries list
# ============================================================================

all_countries = {}
for country in pycountry.countries:
    all_countries[country.alpha_2] = country.name

# Failed countries = all countries - existing countries
failed_countries = set(all_countries.keys()) - existing_countries
print(f"\n⚠️ Countries needing retry: {len(failed_countries)}")

# ============================================================================
# Performance comparison: node-only vs all
# ============================================================================

test_countries = ["US", "CN", "DE", "JP"]  # Test countries
print(f"\n⏱️ Performance comparison test:\n")

test_results = {
    "country": [],
    "strategy": [],
    "count": [],
    "time": []
}

for country_code in test_countries:
    if country_code in all_countries:
        country_name = all_countries[country_code]
        
        # Strategy 1: Node only
        query_node_only = f"""
[out:json][timeout:90];
area["ISO3166-1"="{country_code}"][admin_level=2]->.searchArea;
node["leisure"="dog_park"](area.searchArea);
out;
"""
        
        # Strategy 2: Node + Way
        query_all = f"""
[out:json][timeout:90];
area["ISO3166-1"="{country_code}"][admin_level=2]->.searchArea;
(
  node["leisure"="dog_park"](area.searchArea);
  way["leisure"="dog_park"](area.searchArea);
);
out center;
"""
        
        # Test Node only
        print(f"🧪 {country_code} ({country_name})")
        print(f"   Query: Node only...", end=" ", flush=True)
        start = time.time()
        try:
            resp = requests.post(API_URL, data=query_node_only, timeout=90)
            if resp.status_code == 200:
                data = resp.json()
                count_node = len(data.get("elements", []))
                time_node = time.time() - start
                print(f"✅ {count_node} parks, {time_node:.2f}s")
                test_results["country"].append(country_code)
                test_results["strategy"].append("Node only")
                test_results["count"].append(count_node)
                test_results["time"].append(time_node)
            else:
                print(f"❌ {resp.status_code}")
        except Exception as e:
            print(f"❌ Error")
        
        time.sleep(2)
        
        # Test Node + Way
        print(f"   Query: Node + Way...", end=" ", flush=True)
        start = time.time()
        try:
            resp = requests.post(API_URL, data=query_all, timeout=90)
            if resp.status_code == 200:
                data = resp.json()
                count_all = len(data.get("elements", []))
                time_all = time.time() - start
                print(f"✅ {count_all} parks, {time_all:.2f}s")
                test_results["country"].append(country_code)
                test_results["strategy"].append("Node + Way")
                test_results["count"].append(count_all)
                test_results["time"].append(time_all)
            else:
                print(f"❌ {resp.status_code}")
        except Exception as e:
            print(f"❌ Error")
        
        time.sleep(2)

# Display performance comparison results
if test_results["country"]:
    print(f"\n📊 Performance comparison results:")
    test_df = pd.DataFrame(test_results)
    for country in test_df['country'].unique():
        country_data = test_df[test_df['country'] == country]
        print(f"\n  {country}:")
        for _, row in country_data.iterrows():
            print(f"    • {row['strategy']:15s}: {row['count']:5d} parks, {row['time']:.2f}s")

# ============================================================================
# Re-query failed countries (Priority: key countries first)
# ============================================================================

print(f"\n🔄 Starting re-query of failed countries...\n")

retry_parks = []
success_retry = 0
still_failed = []

# Prioritize key countries - GB and HK first (User's special focus)
priority_countries = ["GB", "HK", "US", "CN", "JP", "IN", "BR", "DE", "FR"]
priority_failed = [c for c in priority_countries if c in failed_countries]
other_failed = [c for c in failed_countries if c not in priority_countries]

retry_order = priority_failed + other_failed

for i, iso_code in enumerate(retry_order):
    if i >= 200:  # Limit retry count, but allow more countries (especially priority ones)
        print(f"\n⏹️ Retried 200 countries, stopping")
        break
    
    country_name = all_countries.get(iso_code, iso_code)
    priority_flag = "🔴" if iso_code in priority_failed else "  "
    
    print(f"[{i+1:2d}] {priority_flag} {iso_code} ({country_name[:20]:20s})", end=" ", flush=True)
    
    query = f"""
[out:json][timeout:90];
area["ISO3166-1"="{iso_code}"][admin_level=2]->.searchArea;
(
  node["leisure"="dog_park"](area.searchArea);
  way["leisure"="dog_park"](area.searchArea);
);
out center;
"""
    
    try:
        response = requests.post(API_URL, data=query, timeout=90)
        
        if response.status_code == 200:
            data = response.json()
            elements = data.get("elements", [])
            
            print(f"✅ {len(elements):4d} parks", flush=True)
            success_retry += 1
            
            # Extract data
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
                    retry_parks.append(park)
                    
                except:
                    continue
                    
        elif response.status_code == 429:
            print(f"⏳ Rate limit", flush=True)
            time.sleep(30)
            still_failed.append(iso_code)
        else:
            print(f"❌ {response.status_code}", flush=True)
            still_failed.append(iso_code)
            
    except Exception as e:
        print(f"❌ Exception", flush=True)
        still_failed.append(iso_code)
    
    time.sleep(1.5)

# ============================================================================
# Merge data and save
# ============================================================================

print(f"\n" + "="*70)
print(f"\n💾 Merging data...\n")

if retry_parks:
    # Merge new and old data
    retry_df = pd.DataFrame(retry_parks)
    merged_df = pd.concat([existing_df, retry_df], ignore_index=True)
    
    # Deduplicate (based on osm_id)
    merged_df = merged_df.drop_duplicates(subset=['osm_id'], keep='first')
    
    print(f"✅ Re-query found: {len(retry_df)} new parks")
    print(f"✅ Total (deduplicated): {len(merged_df):,} parks")
    
    # Save merged data
    csv_file = "output/pet_parks_by_country_updated.csv"
    merged_df.to_csv(csv_file, index=False)
    print(f"✅ Saved updated CSV: {csv_file}")
    
    # Generate GeoJSON
    features = []
    for _, row in merged_df.iterrows():
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
                "osm_type": row["osm_type"],
            }
        }
        features.append(feature)
    
    geojson = {
        "type": "FeatureCollection",
        "properties": {
            "title": "Global Dog Parks Dataset (Updated)",
            "total_parks": len(merged_df),
            "countries_covered": merged_df["country_code"].nunique(),
            "update_timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "node_count": len(merged_df[merged_df['osm_type']=='node']),
            "way_count": len(merged_df[merged_df['osm_type']=='way']),
        },
        "features": features
    }
    
    geojson_file = "output/pet_parks_by_country_updated.geojson"
    with open(geojson_file, "w", encoding="utf-8") as f:
        json.dump(geojson, f, indent=2, ensure_ascii=False)
    print(f"✅ Saved GeoJSON: {geojson_file}")
    
    # Detailed statistics
    print(f"\n📊 Updated statistics:")
    print(f"  • Total parks: {len(merged_df):,}")
    print(f"  • Countries covered: {merged_df['country_code'].nunique()}")
    print(f"  • Node type: {len(merged_df[merged_df['osm_type']=='node']):,} ({len(merged_df[merged_df['osm_type']=='node'])/len(merged_df)*100:.1f}%)")
    print(f"  • Way type: {len(merged_df[merged_df['osm_type']=='way']):,} ({len(merged_df[merged_df['osm_type']=='way'])/len(merged_df)*100:.1f}%)")
    
    print(f"\n🔎 Key countries data (Updated) - User focus: GB UK, HK Hong Kong:")
    for code, name in key_countries.items():
        count = len(merged_df[merged_df['country_code'] == code])
        node_count = len(merged_df[(merged_df['country_code'] == code) & (merged_df['osm_type']=='node')])
        way_count = len(merged_df[(merged_df['country_code'] == code) & (merged_df['osm_type']=='way')])
        status = "✅" if count > 0 else "❌"
        priority_flag = "🔴" if code in ["GB", "HK"] else "  "
        print(f"  {priority_flag} {status} {code:2s}: {count:5d} parks (Node:{node_count:4d}, Way:{way_count:4d})")
    
    print(f"\n🌍 Distribution by Country (TOP 20):")
    country_stats = merged_df["country_name"].value_counts().head(20)
    for idx, (country, count) in enumerate(country_stats.items(), 1):
        bar_length = min(count // 50, 30)
        bar = "█" * bar_length
        print(f"  {idx:2d}. {country:25s}: {count:5d} parks  {bar}")
    
    if still_failed:
        print(f"\n⚠️ Still failed countries ({len(still_failed)}):")
        for iso in still_failed[:15]:
            print(f"  • {iso} ({all_countries.get(iso, 'Unknown')})")
        if len(still_failed) > 15:
            print(f"  ... and {len(still_failed) - 15} more")
else:
    print("❌ Re-query found no new data")

print(f"\n" + "="*70)
print(f"\n✅ Complete!")
