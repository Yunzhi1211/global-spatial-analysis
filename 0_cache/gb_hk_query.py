#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
专门查询 GB (英国) 和 HK (香港) 的狗公园
快速脚本 - 只关注这两个关键国家
"""

import requests
import json
import time
import pandas as pd

print("\n🐕 查询 GB(英国) 和 HK(香港) 狗公园\n" + "="*60)

# 多个 API 镜像（从最稳定的开始）
API_URLS = [
    "https://overpass-api.de/api/interpreter",        # 主服务器
    "http://overpass.kumi.systems/api/interpreter",   # HTTP 版本（更稳定）
    "https://z.overpass-api.de/api/interpreter",      # 备用
]

# 创建 session 以复用连接
session = requests.Session()
session.headers.update({
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
})

# 加载现有数据
existing_df = pd.read_csv("output/pet_parks_by_country.csv")
print(f"📊 已有数据: {len(existing_df):,} 个公园")

# 检查 GB 和 HK 现有的数据
gb_existing = len(existing_df[existing_df['country_code'] == 'GB'])
hk_existing = len(existing_df[existing_df['country_code'] == 'HK'])
print(f"  • GB (英国): {gb_existing} 个")
print(f"  • HK (香港): {hk_existing} 个\n")

# ============================================================================
# 查询 GB 和 HK
# ============================================================================

countries_to_query = {
    "GB": "United Kingdom",
    "HK": "Hong Kong"
}

new_parks = []

for iso_code, country_name in countries_to_query.items():
    print(f"🔍 查询: {iso_code} ({country_name})")
    
    # 分开查询：先查 node，再查 way（简化查询，提高成功率）
    queries = {
        "node": f"""
[out:json][timeout:120];
area["ISO3166-1"="{iso_code}"][admin_level=2]->.searchArea;
node["leisure"="dog_park"](area.searchArea);
out;
""",
        "way": f"""
[out:json][timeout:120];
area["ISO3166-1"="{iso_code}"][admin_level=2]->.searchArea;
way["leisure"="dog_park"](area.searchArea);
out center;
"""
    }
    
    country_parks = []
    
    for query_type, query in queries.items():
        print(f"  📌 查询 {query_type}...", end=" ", flush=True)
        
        success = False
        for attempt in range(5):  # 最多 5 次重试
            
            for api_url in API_URLS:
                try:
                    # 增加超时和重试
                    response = session.post(
                        api_url, 
                        data=query, 
                        timeout=(10, 120)  # (连接超时, 读取超时)
                    )
                    
                    if response.status_code == 200:
                        data = response.json()
                        elements = data.get("elements", [])
                        print(f"✅ {len(elements)} 个")
                        success = True
                        
                        # 提取公园数据
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
                                country_parks.append(park)
                            except:
                                continue
                        break
                        
                    elif response.status_code == 429:
                        continue  # 换下一个 API
                    elif response.status_code == 504:
                        continue  # 换下一个 API
                        
                except Exception:
                    continue  # 换下一个 API
            
            if success:
                break
            
            # 失败了就等等再试
            if attempt < 4:
                wait_time = 10 + attempt * 5  # 10, 15, 20, 25 秒
                print(f"  ⏳ {wait_time}秒后重试...", end=" ", flush=True)
                time.sleep(wait_time)
        
        if not success:
            print(f"❌ 失败（所有镜像都无响应）")
        
        time.sleep(3)  # API 调用间隔
    
    new_parks.extend(country_parks)
    print()

# ============================================================================
# 合并并保存
# ============================================================================

print(f"\n" + "="*60)
print(f"\n💾 数据处理...\n")

if new_parks:
    # 创建新数据的 DataFrame
    new_df = pd.DataFrame(new_parks)
    
    # 合并
    merged_df = pd.concat([existing_df, new_df], ignore_index=True)
    
    # 去重
    merged_df = merged_df.drop_duplicates(subset=['osm_id'], keep='first')
    
    print(f"✅ 新增公园: {len(new_df)}")
    print(f"✅ 总公园数: {len(merged_df):,}")
    
    # 保存
    csv_file = "output/pet_parks_by_country_updated.csv"
    merged_df.to_csv(csv_file, index=False)
    print(f"✅ 保存: {csv_file}")
    
    # 保存 GeoJSON
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
            "title": "Global Dog Parks Dataset (GB & HK Updated)",
            "total_parks": len(merged_df),
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        },
        "features": features
    }
    
    geojson_file = "output/pet_parks_by_country_updated.geojson"
    with open(geojson_file, "w", encoding="utf-8") as f:
        json.dump(geojson, f, indent=2, ensure_ascii=False)
    print(f"✅ 保存: {geojson_file}")
    
    # 统计
    print(f"\n📊 最终统计:")
    gb_total = len(merged_df[merged_df['country_code'] == 'GB'])
    hk_total = len(merged_df[merged_df['country_code'] == 'HK'])
    print(f"  • GB (英国): {gb_total} 个")
    print(f"  • HK (香港): {hk_total} 个")
    
    gb_new = gb_total - gb_existing
    hk_new = hk_total - hk_existing
    print(f"\n  新增:")
    print(f"  • GB: +{gb_new}")
    print(f"  • HK: +{hk_new}")
    
else:
    print("❌ 没有找到新数据")

print(f"\n" + "="*60)
print(f"\n✅ 完成!")

