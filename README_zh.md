[English](README.md) | [简体中文](README_zh.md)

# 全球犬类公园可达性分析项目

本项目面向 195+ 国家，基于 OpenStreetMap 犬类公园数据与国家层级指标，开展全球比较分析与可视化展示。

## 项目范围

- 覆盖国家：195+
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
3. 打开 3_output/10_fancy_dashboard.html 查看页面。

## 关键输出文件

- 3_output/01_master_global_dataset.csv：整合后的主数据集
- 3_output/04_global_ranking_full.csv：完整全球排名
- 3_output/03_peer_country_groups.csv：同群国家结果
- 3_output/05_country_clusters_kmeans.csv：聚类结果
- 3_output/10_fancy_dashboard.html：交互式页面

## 方法概述

- 数据来源：OpenStreetMap 犬类公园相关标签
- 指标标准化：按每 10 万人口归一化
- 比较逻辑：跨国统一指标缩放与排序
- 分组方法：K-means 聚类识别国家类型

## 当前 AI Insights 说明

当前仪表板中的 AI Insights 由前端 JavaScript 模板生成，基于你选择的国家与已有数据字段拼接文本。默认没有接入在线大模型 API。

## 限制说明

- OSM 在不同国家覆盖度不一致
- 数据质量受标签完整性与地理编码影响
- 结果适合比较与方向性判断，不等于因果结论

## 维护建议

- 最近一次主要更新：2026
- 当数据源更新后，建议重新跑完整流程
