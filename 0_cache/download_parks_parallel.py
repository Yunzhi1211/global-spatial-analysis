#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
全球狗公园数据下载脚本 (Python版 - 改进版，多实例+稳定重试)
"""

import json
import time
from datetime import datetime
import pandas as pd
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed
from random import shuffle

print("\n🐕 全球狗公园数据下载 - Python版 (改进版)\n")
print("=" * 70)

# ============================================================================
# 多个Overpass API实例 (负载均衡)
# ============================================================================
OVERPASS_INSTANCES = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://z.overpass-api.de/api/interpreter",
]

# ============================================================================
# 全球主要城市列表
# ============================================================================

cities = [
    # 北美
    {"name": "San Francisco", "lat": 37.7749, "lon": -122.4194, "country": "USA", "radius": 50},
    {"name": "New York", "lat": 40.7128, "lon": -74.0060, "country": "USA", "radius": 30},
    {"name": "Los Angeles", "lat": 34.0522, "lon": -118.2437, "country": "USA", "radius": 40},
    {"name": "Chicago", "lat": 41.8781, "lon": -87.6298, "country": "USA", "radius": 30},
    {"name": "Toronto", "lat": 43.6532, "lon": -79.3832, "country": "Canada", "radius": 30},
    {"name": "Vancouver", "lat": 49.2827, "lon": -123.1207, "country": "Canada", "radius": 30},
    
    # 欧洲
    {"name": "London", "lat": 51.5074, "lon": -0.1278, "country": "UK", "radius": 25},
    {"name": "Berlin", "lat": 52.5200, "lon": 13.4050, "country": "Germany", "radius": 25},
    {"name": "Paris", "lat": 48.8566, "lon": 2.3522, "country": "France", "radius": 25},
    {"name": "Amsterdam", "lat": 52.3676, "lon": 4.9041, "country": "Netherlands", "radius": 20},
    
    # 亚洲
    {"name": "Hong Kong", "lat": 22.3193, "lon": 114.1694, "country": "Hong Kong", "radius": 30},
    {"name": "Tokyo", "lat": 35.6762, "lon": 139.6503, "country": "Japan", "radius": 30},
    {"name": "Seoul", "lat": 37.5665, "lon": 126.9780, "country": "South Korea", "radius": 25},
    {"name": "Singapore", "lat": 1.3521, "lon": 103.8198, "country": "Singapore", "radius": 15},
    {"name": "Bangkok", "lat": 13.7563, "lon": 100.5018, "country": "Thailand", "radius": 25},
    {"name": "Shanghai", "lat": 31.2304, "lon": 121.4737, "country": "China", "radius": 30},
    
    # 澳洲
    {"name": "Sydney", "lat": -33.8688, "lon": 151.2093, "country": "Australia", "radius": 30},
    {"name": "Melbourne", "lat": -37.8136, "lon": 144.9631, "country": "Australia", "radius": 30},
]

# ============================================================================
# Overpass API 查询 (改进版 - 多实例+稳定重试)
# ============================================================================

def query_dog_parks(city_data, retry_count=0, max_retries=3):
    """查询单个城市的狗公园 - 带重试和负载均衡"""
    city_name = city_data["name"]
    lat = city_data["lat"]
    lon = city_data["lon"]
    country = city_data["country"]
    radius_km = city_data["radius"]
    
    # 计算边界框
    radius_deg = radius_km / 111
    bbox = f"{lat - radius_deg},{lon - radius_deg},{lat + radius_deg},{lon + radius_deg}"
    
    # 使用随机Overpass实例 (负载均衡)
    overpass_url = OVERPASS_INSTANCES[hash(city_name) % len(OVERPASS_INSTANCES)]
    
    # 更简化的查询 (减少服务器负担)
    query = f"""
    [timeout:30];
    [bbox:{bbox}];
    (
      node["amenity"="dog_park"];
      way["amenity"="dog_park"];
    );
    out center;
    """
    
    try:
        print(f"🔍 {city_name}...", end=" ", flush=True)
        response = requests.post(overpass_url, data=query, timeout=30)
        
        # 检查响应是否为空
        if not response.text or response.text.strip() == "":
            print(f"⚠️  空响应", flush=True)
            if retry_count < max_retries:
                print(f"  ↻ 重试 ({retry_count+1}/{max_retries})...", flush=True)
                time.sleep(5 + retry_count * 3)  # 指数退避
                return query_dog_parks(city_data, retry_count + 1, max_retries)
            return []
        
        if response.status_code == 200:
            try:
                data = response.json()
                elements = data.get("elements", [])
                
                parks = []
                for elem in elements:
                    if elem["type"] == "node":
                        parks.append({
                            "name": elem.get("tags", {}).get("name", "Unnamed Dog Park"),
                            "latitude": elem["lat"],
                            "longitude": elem["lon"],
                            "city": city_name,
                            "country": country,
                            "data_source": "OpenStreetMap (Overpass)",
                            "confidence_score": 0.85,
                        })
                
                if parks:
                    print(f"✅ {len(parks)} 个", flush=True)
                else:
                    print(f"⚠️  无数据", flush=True)
                return parks
                
            except json.JSONDecodeError as e:
                print(f"❌ JSON解析失败", flush=True)
                if retry_count < max_retries:
                    print(f"  ↻ 重试 ({retry_count+1}/{max_retries})...", flush=True)
                    time.sleep(5 + retry_count * 3)
                    return query_dog_parks(city_data, retry_count + 1, max_retries)
                return []
                
        elif response.status_code == 429:
            wait_time = 15 + retry_count * 10
            print(f"⏳ 限流，等待{wait_time}秒...", flush=True)
            time.sleep(wait_time)
            return query_dog_parks(city_data, retry_count, max_retries)
            
        elif response.status_code == 504:
            print(f"❌ 504 服务器过载", flush=True)
            if retry_count < max_retries:
                wait_time = 10 + retry_count * 5
                print(f"  ↻ {wait_time}秒后重试...", flush=True)
                time.sleep(wait_time)
                return query_dog_parks(city_data, retry_count + 1, max_retries)
            return []
        else:
            print(f"❌ {response.status_code}", flush=True)
            return []
            
    except requests.exceptions.Timeout:
        print(f"⏱️  超时", flush=True)
        if retry_count < max_retries:
            time.sleep(5 + retry_count * 2)
            return query_dog_parks(city_data, retry_count + 1, max_retries)
        return []
        
    except Exception as e:
        print(f"❌ {str(e)[:30]}", flush=True)
        return []

# ============================================================================
# 并行下载 (改进版 - 减少并发，增加延迟)
# ============================================================================

print(f"\n🌍 开始并行查询 {len(cities)} 个城市...\n")
print("⚙️  配置: 2个工作线程，城市间延迟 1秒\n")

all_parks = []
with ThreadPoolExecutor(max_workers=2) as executor:  # 减少到2个线程
    futures = []
    for i, city in enumerate(cities):
        future = executor.submit(query_dog_parks, city)
        futures.append((future, city["name"]))
        time.sleep(0.5)  # 提交间延迟
    
    for future, city_name in futures:
        try:
            parks = future.result()
            all_parks.extend(parks)
            time.sleep(1)  # 完成后等待1秒
        except Exception as e:
            print(f"❌ {city_name} 错误: {e}")

# ============================================================================
# 导出
# ============================================================================

print(f"\n\n💾 导出 {len(all_parks)} 个狗公园...\n")

if all_parks:
    df = pd.DataFrame(all_parks)
    
    # 保存为CSV
    csv_file = "output/pet_parks_python_parallel.csv"
    df.to_csv(csv_file, index=False)
    print(f"✅ CSV: {csv_file}")
    
    # 转为GeoJSON
    geojson = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [row["longitude"], row["latitude"]]
                },
                "properties": {
                    "name": row["name"],
                    "city": row["city"],
                    "country": row["country"],
                    "data_source": row["data_source"],
                    "confidence_score": row["confidence_score"]
                }
            }
            for _, row in df.iterrows()
        ]
    }
    
    geojson_file = "output/pet_parks_python_parallel.geojson"
    with open(geojson_file, "w") as f:
        json.dump(geojson, f, indent=2)
    print(f"✅ GeoJSON: {geojson_file}")
    
    # 统计
    print(f"\n📊 统计结果\n" + "=" * 70)
    print(f"总计: {len(all_parks)} 个狗公园")
    print(f"国家: {df['country'].nunique()} 个")
    print(f"城市: {df['city'].nunique()} 个")
    print(f"\n按国家分布:")
    print(df.groupby("country").size().sort_values(ascending=False))
    
    print(f"\n🎉 完成!")
    print("现在可以打开: http://localhost:8000/dog_park_finder.html")
else:
    print("❌ 未找到任何数据")

