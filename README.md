<img width="1179" height="2556" alt="ff4bc32ca260a9cd2d026178f67d3f33" src="https://github.com/user-attachments/assets/4c81a1e8-aa7a-475d-b7e9-5fed559859aa" />
# StarChaser - Your Personal Stargazing Guide

<p align="center">
  <a href="#english">English</a> · <a href="#chinese">中文</a>
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/9f4ca86d-ce6d-40cb-80a2-cd0b1ffd06cd" width="200" alt="StarChaser Icon">
</p>

<a id="english"></a>

<p align="center">
  <b>Explore darker skies and plan better nights under the Milky Way. StarChaser is a professional iOS companion for astrophotographers and astronomy enthusiasts.</b>
</p>

---

## Overview

**StarChaser** helps photographers make practical night-sky decisions with visual maps, astronomy calculations, weather data, moon phase analysis, and camera exposure tools. It is designed for mirrorless cameras, DSLRs, film cameras, and mobile-assisted planning.

The sky forecast feature does **not** use an AI model. It uses a transparent rule-based scoring method that combines nearby scenic POIs, light pollution, weather, moonlight, and distance.

---

## Core Features

### Light Pollution Map

* **Interactive dark-sky map**: View light pollution layers and compare observing areas visually.
* **Bortle class reading**: Tap a location to estimate its Bortle class and understand how suitable it is for Milky Way, wide-field, or bright-object observing.

### Sky Forecast

* **Nearby observing spot search**: Searches scenic viewpoints, scenic areas, campsites, mountain areas, forest parks, and lakes within the current 100 km planning range.
* **Rule-based ranking**: Scores each candidate using light pollution, 5-day hourly weather, local moon phase and moon altitude, visibility, humidity, wind, and distance.
* **Practical observing advice**: Recommendation text changes by Bortle level, so heavily polluted areas are not described as ideal Milky Way locations.

### Lunar Cycle

* **Moon phase tracking**: Check the current moon phase, illumination, altitude, and rise/set timing.
* **Planning support**: Use moonlight interference and phase trends to plan darker shooting windows.

### Photographic Meter

* **Phone-based metering reference**: Uses the phone camera as a brightness reference for night shooting.
* **Exposure relationship tools**: Aperture, ISO, shutter speed, and exposure compensation are linked, so changing one parameter updates the others.
* **Digital and film support**: Provides guidance for mirrorless/DSLR cameras and film stocks, including reciprocity failure considerations.

---<img width="1179" height="2556" alt="7bfea7ade4437d950e0389c210f797d9"  />




<div align="center">
<img width="300" alt="05bfe41bb3654c6f4c1f9d2bbe77cc06" src="https://github.com/user-attachments/assets/d7ef0351-65dc-4afa-9353-0de51457097e" />
<img width="300" alt="968f6444acac1e61d1ecf3347ee7a9b3" src="https://github.com/user-attachments/assets/9ba0e8c9-66c1-4b04-ab69-d894d899e103" />
<img width="300" alt="8706ca76d902f08192320b62d2676f43" src="https://github.com/user-attachments/assets/3e5614ea-a4c0-4e7e-842e-ccaf24a5f525" />
<img width="300" alt="4d8362161b1f47cb27656f3d169bb433" src="https://github.com/user-attachments/assets/9544bd9c-8254-4228-8791-5aa65abd3544" />
<img width="300" alt="6248578712ced7ea627d6bc2843647bf" src="https://github.com/user-attachments/assets/f1125ee0-6bbe-4458-9f4d-49d3a29b45b0" />
<img width="300" alt="258f6836f2131b6f8c2516c5190d4282" src="https://github.com/user-attachments/assets/31f40d62-e6bd-4b11-97c6-57e6c19387e0" /><img width="1179" height="2556" alt="76c414b58efae8355bed9444557076f4" src="https://github.com/user-attachments/assets/19fca71f-2640-465d-8a30-3a5b52ef283d" />

<img width="300" alt="258f6836f2131b6f8c2516c5190d4282" src="https://github.com/user-attachments/assets/392ecb73-ad1b-487c-8f8b-bde42126a828" />
</div>

---

## Forecast Method

StarChaser's observing forecast is intentionally transparent:

1. It uses the user's location to query nearby scenic POIs through the AMap Web Service.
2. It estimates each candidate's light pollution and Bortle class.
3. It requests 5-day hourly weather from Open-Meteo, including cloud cover, humidity, visibility, wind, and precipitation probability.
4. It calculates moon phase, illumination, and moon altitude locally.
5. It ranks candidates with weighted rules, giving the strongest weight to darkness and then considering clouds, moonlight, humidity, visibility, wind, and distance.

This makes the result explainable and predictable instead of relying on a black-box AI recommendation.

---

## Local API Key Setup

The real API key file is intentionally ignored by git:

```text
StarChaser/Config/APIKeys.plist
```

To run the sky forecast module locally:

1. Copy the example file:

```bash
cp StarChaser/Config/APIKeys.example.plist StarChaser/Config/APIKeys.plist
```

2. Replace the placeholder value:

```xml
<key>AMapWebServiceKey</key>
<string>YOUR_AMAP_WEB_SERVICE_KEY</string>
```

3. Keep `StarChaser/Config/APIKeys.plist` private. Only the example file should be committed.

StarChaser currently uses the AMap Web Service key for nearby POI search. The Open-Meteo weather request does not require an API key.

---

## App Store Plan

StarChaser is being prepared for Apple App Store release. The project is still being refined for performance, bilingual copy, and production readiness.

---

## Feedback

If you are interested in astrophotography or night-sky planning, feedback and suggestions are welcome through GitHub Issues.

---

## License

This project is source-available for non-commercial use under the [PolyForm Noncommercial License 1.0.0](./LICENSE). Commercial use, resale, or integration into commercial products requires separate permission from the StarChaser Team.

---

<p align="center">
  © 2026 StarChaser Team
</p>

<a id="chinese"></a>

# StarChaser - 您的私人星空观测指南

<p align="center">
  <a href="#english">English</a> · <a href="#chinese">中文</a>
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/9f4ca86d-ce6d-40cb-80a2-cd0b1ffd06cd" width="200" alt="StarChaser Icon">
</p>

<p align="center">
  <b>探索暗夜，追随银河。StarChaser 是一款专为星空摄影师和天文爱好者打造的专业级 iOS 应用。</b>
</p>

---

## 应用简介

**StarChaser** 通过地图可视化、天文计算、天气数据、月相分析和相机曝光工具，帮助摄影师更好地规划星空拍摄。无论您使用的是无反相机、单反、胶片机，还是希望用手机辅助测光，StarChaser 都能提供更清晰的拍摄决策参考。

观星预测功能**不使用 AI 模型**。它采用透明的规则评分方法，综合周边景点候选地、光污染、天气、月光干扰和距离来生成推荐。

---

## 核心功能

### 光污染地图

* **交互式暗夜地图**：直观查看光污染图层，对比不同区域的暗空条件。
* **Bortle 等级读取**：点击地图位置即可估算 Bortle 波特尔暗空等级，判断该地点更适合银河、星野还是亮目标观测。

### 观星预测

* **附近观测点搜索**：在当前固定 100 km 规划范围内，搜索观景台、景区、露营地、山地、森林公园和湖泊等候选地点。
* **规则化评分**：结合光污染、5 天天气预报、本地月相与月亮高度、能见度、湿度、风速和距离进行排序。
* **实用观测建议**：推荐文字会根据 Bortle 等级变化，光污染严重的区域不会被写成适合银河主拍地点。

### 月相追踪

* **月相状态**：查看当前月相、照明比例、月亮高度和升落时间。
* **拍摄规划**：结合月光干扰和月相变化，提前选择更暗的拍摄窗口。

### 专业相机测光助手

* **手机测光参考**：使用手机相机读取环境亮度，为夜间拍摄提供参考。
* **曝光参数联动**：光圈、ISO、快门和曝光补偿会相互制约，调整其中一项时自动换算其他参数。
* **数码与胶片支持**：支持无反/单反相机和胶片模式，并考虑胶片倒易律失效带来的曝光修正。

---

## 功能预览



<div align="center">
<img width="300" alt="05bfe41bb3654c6f4c1f9d2bbe77cc06" src="https://github.com/user-attachments/assets/4c269bc6-e588-4395-bf90-47dfd6384156" />
<img width="300" alt="968f6444acac1e61d1ecf3347ee7a9b3" src="https://github.com/user-attachments/assets/4d2a42be-ee3f-4167-b8eb-89e8246a54b2" />
<img width="300" alt="8706ca76d902f08192320b62d2676f43" src="https://github.com/user-attachments/assets/5be55ce8-f34d-4b28-8d24-15ab01d07ee9" />
<img width="300" alt="4d8362161b1f47cb27656f3d169bb433" src="https://github.com/user-attachments/assets/7d063bd5-1006-4de8-87d2-4dcb2c853280" />
<img width="300" alt="6248578712ced7ea627d6bc2843647bf" src="https://github.com/user-attachments/assets/d4ebf84e-f006-456c-926d-a09d369c2e97" />
<img width="300" alt="258f6836f2131b6f8c2516c5190d4282" src="https://github.com/user-attachments/assets/919c039f-c249-43d0-8ec2-1ec52d93ed80" />
<img width="300" alt="c19b673ec99d35979d578d9ae4c29a68" src="https://github.com/user-attachments/assets/cabd3c71-961c-4482-8d74-ad4b5707a2ac" />
</div>

---

## 预测方法

StarChaser 的观星预测是可解释的规则评分：

1. 根据用户位置，通过高德 Web 服务查询附近景区类 POI。
2. 估算每个候选地点的光污染和 Bortle 等级。
3. 请求 Open-Meteo 的 5 天小时级天气数据，包括云量、湿度、能见度、风速和降水概率。
4. 在本地计算月相、月亮照明比例和月亮高度。
5. 使用加权规则给候选地点排序，其中暗空条件权重最高，其次考虑云量、月光、湿度、能见度、风速和距离。

因此结果更容易解释和复查，而不是依赖黑盒式 AI 推荐。

---

## 本地 API Key 配置

真实 API key 文件已经被 git 忽略：

```text
StarChaser/Config/APIKeys.plist
```

如果要在本地运行观星预测模块：

1. 复制示例文件：

```bash
cp StarChaser/Config/APIKeys.example.plist StarChaser/Config/APIKeys.plist
```

2. 替换里面的占位值：

```xml
<key>AMapWebServiceKey</key>
<string>YOUR_AMAP_WEB_SERVICE_KEY</string>
```

3. 请保持 `StarChaser/Config/APIKeys.plist` 只存在于本地，不要提交真实 key。仓库里只提交示例文件即可。

StarChaser 目前使用高德 Web 服务 Key 获取周边 POI。Open-Meteo 天气请求不需要 API key。

---

## App Store 计划

StarChaser 正在为 Apple App Store 上架做准备，目前重点打磨性能、双语文案和正式版本体验。

---

## 开发与反馈

如果您是星空摄影爱好者，或对本项目感兴趣，欢迎通过 GitHub Issues 提交建议或反馈。

---

## 许可证

本项目源码按 [PolyForm Noncommercial License 1.0.0](./LICENSE) 提供，仅允许非商业用途使用。商业使用、转售或集成到商业产品中，需要事先获得 StarChaser Team 的单独授权。

---

<p align="center">
  © 2026 StarChaser Team | 记录星空，追随永恒
</p>
