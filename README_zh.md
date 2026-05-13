[English](README.md) | [简体中文](README_zh.md)

# 全球犬类公园可达性分析项目

本项目面向 100+ 国家，基于 OpenStreetMap 犬类公园数据与国家层级指标，开展全球比较分析与可视化展示。

## 项目范围

- 覆盖国家：100+
- 分析粒度：国家层面
- 核心指标：每 10 万人口犬类公园数
- 主要产出：全球排名、区域比较、聚类分组、交互式仪表板

## 仓库结构

- 0_cache：缓存数据、历史脚本与本地工具
- 1_python_data_collection：Python 数据采集脚本
- 2_R_script：R 分析主流程
- 3_output：结果数据、报告与仪表板文件

## 分析流程

- 00_setup.R：环境初始化与公共函数
- 01_global_data_integration.R：国家级整合与主数据集生成
- 02_exploratory_analysis_global.R：描述性统计与探索分析
- 03_regional_analysis.R：区域差异与同群国家分析
- 04_global_ranking.R：全球排名与分层
- 05_country_clustering.R：K-means 聚类分组
- 06_interactive_global_dashboard.R：仪表板相关输出
- RUN_ALL_ANALYSIS_GLOBAL.R：一键全流程执行

## 快速开始

1. 使用 VS Code 或 RStudio 打开本项目。
2. 运行 2_R_script/RUN_ALL_ANALYSIS_GLOBAL.R。
3. 打开 3_output/global_dog_parks_dashboard.html 查看页面。

## Python 采集脚本模式

Python 采集逻辑已统一到 1_python_data_collection/api_global_mega.py。

- 全量采集（全部 ISO 代码元素）：
	- python 1_python_data_collection/api_global_mega.py --mode full
- US/HK 定向补抓并合并到现有输出：
	- python 1_python_data_collection/api_global_mega.py --mode targeted
- 仅补抓 HK：
	- python 1_python_data_collection/api_global_mega.py --mode targeted --only-hk
- 仅补抓 US：
	- python 1_python_data_collection/api_global_mega.py --mode targeted --only-us

定向模式会在现有输出文件上原地更新，并同步刷新覆盖状态。

## ISO 3166-1 口径定义

本项目按 ISO 3166-1 alpha-2 代码元素进行全球国家/地区范围定义。

- 口径基础：国家与地区代码元素
- 当前流程总量：249
- 重要说明：该口径不等于主权国家数量

该定义会自动写入输出元数据：

- 3_output/dashboard/pet_parks_by_country.geojson（FeatureCollection 的 properties）
- 3_output/dashboard/dataset_metadata.json（结构化元数据摘要）

## 关键输出文件

- 3_output/dashboard/pet_parks_by_country.csv：最新 mega 采集 CSV 输出
- 3_output/dashboard/pet_parks_by_country.geojson：最新 mega 采集 GeoJSON 输出
- 3_output/dashboard/country_coverage_report.csv：按 ISO 代码的覆盖状态
- 3_output/dashboard/dataset_metadata.json：ISO 口径定义与运行摘要
- 3_output/global_dog_parks_dashboard.html：交互式页面

此前在 3_output 下的历史生成文件已归档到：

- 0_cache/3_output_archive_20260510

## 方法概述

- 数据来源：OpenStreetMap 犬类公园相关标签
- 指标标准化：按每 10 万人口归一化
- 比较逻辑：跨国统一指标缩放与排序
- 分组方法：K-means 聚类识别国家类型

## 限制说明

- OSM 在不同国家覆盖度不一致
- 数据质量受标签完整性与地理编码影响
- 结果适合比较与方向性判断，不等于因果结论

## 维护建议

- 最近一次主要更新：2026.5
- 当数据源更新后，建议重新跑完整流程
