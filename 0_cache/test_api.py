#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
诊断脚本 - 测试Overpass API连接
"""

import requests
import json

print("\n🔍 Overpass API 诊断\n" + "="*70)

# 测试不同的Overpass实例
endpoints = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://z.overpass-api.de/api/interpreter",
]

# 最简单的查询：查询一个特定的node ID
simple_query = "[out:json];node(1);out;"

for url in endpoints:
    print(f"\n🌐 测试: {url}")
    print("  ", "-" * 60)
    
    try:
        print("  ↳ 发送请求...", end=" ", flush=True)
        response = requests.post(url, data=simple_query, timeout=10)
        
        print(f"状态码: {response.status_code}")
        print(f"  ↳ 响应大小: {len(response.text)} 字节")
        
        if response.status_code == 200:
            print(f"  ↳ ✅ 连接成功！")
            try:
                data = response.json()
                print(f"  ↳ 返回JSON格式: ✅")
                print(f"  ↳ 包含 {len(data.get('elements', []))} 个元素")
            except:
                print(f"  ↳ 返回非JSON内容")
        else:
            print(f"  ↳ ❌ 错误: {response.status_code}")
            print(f"  ↳ 响应内容: {response.text[:200]}")
            
    except requests.exceptions.Timeout:
        print(f"  ❌ 超时 (10秒)")
    except requests.exceptions.ConnectionError as e:
        print(f"  ❌ 连接错误: {str(e)[:50]}")
    except Exception as e:
        print(f"  ❌ 错误: {str(e)[:50]}")

print("\n" + "="*70)
print("\n根据上面的结果:")
print("✅ 如果有一个显示'连接成功'和'返回JSON格式' → API能用")
print("❌ 如果全部失败 → 可能是网络问题或被封IP")
