# 茶園 N2O 預測模型與研究資訊總整理

## 一、文件目的

本文件整合目前茶園 N2O 排放研究的研究背景、資料來源、模型結構、分析流程、主要結果、圖表輸出與應用意涵，作為論文撰寫、口試報告與後續模型優化的統一參考版本。

## 二、研究主題與核心問題

本研究以茶園土壤 N2O 排放與土壤有機碳含量為核心，探討不同栽培模式與施肥管理對碳排放與碳匯之影響，並進一步建立 N2O 預測模型，以回答下列問題：

1. 茶園在不同氮肥條件下，N2O 排放量如何變化。
2. 降雨、氣溫、土壤溫度與施肥量是否可解釋 N2O 排放變異。
3. 茶園 N2O 排放是否具有降雨脈衝特性。
4. 是否可建立管理導向的預測模型，作為施肥時機與減排評估依據。

## 三、研究背景

茶樹為我國重要經濟作物，為維持茶菁產量，茶園通常需施用大量氮肥。然而，氮肥投入可能促進土壤排放一氧化二氮（N2O），增加農業溫室氣體排放風險。根據 IPCC 第六次評估報告，N2O 之 100 年暖化潛勢約為 CO2 的 273 倍，因此茶園施肥管理不僅關係作物生產，也與農業淨零排放、碳收支與土地永續利用密切相關。

本研究的田間結果指出，有機茶園與慣行茶園在相同施氮量條件下，全年 N2O 排放量與土壤有機碳含量存在明顯差異。有機茶園全年 N2O 排放量為 12.3 kg ha^-1，慣行茶園為 7.03 kg ha^-1；折算為 CO2e 分別為 3.36 與 1.92 t CO2e ha^-1。有機茶園之 N2O 排放量約為慣行茶園 1.75 倍。另一方面，土壤深度 30 cm 之土壤有機碳含量在有機茶園與慣行茶園分別為 84.16 與 56.98 t C ha^-1，有機茶園高出 27.18 t C ha^-1。整體而言，有機茶園雖伴隨較高 N2O 排放，但亦具有顯著較高之碳匯能力。

## 四、目前模型的角色定位

目前建立的模型屬於「茶園 N2O 排放預測模型」，其目的不是直接比較有機與慣行兩種栽培制度的碳收支，而是利用實測 N2O 排放資料與逐日氣象資料，建立一套可解釋與預測 N2O 排放變動的統計架構。這個模型可作為：

1. 解釋茶園 N2O 排放的驅動因子。
2. 識別高排放風險時段。
3. 支援施肥與降雨管理。
4. 作為後續擴充到碳收支整合模型的基礎。

## 五、資料來源與檔案結構

### 1. N2O 觀測資料

目前模型使用五個處理檔案：

- `D:\tea\0311_A.xlsx`
- `D:\tea\0311_B.xlsx`
- `D:\tea\0311_C.xlsx`
- `D:\tea\0311_D.xlsx`
- `D:\tea\0311_E.xlsx`

五個檔案之欄位結構一致，欄位如下：

- `date`
- `temp_out`
- `hum_out`
- `light_out`
- `wind_out`
- `rain`
- `soil_temp_A`
- `soil_moist_A`
- `N2O_flux`

每個檔案共有 366 列，代表以逐日尺度整理之觀測資料。模型實際使用時，將五個檔案合併後，依處理給定下列施肥量：

- A = 0 kg N ha^-1
- B = 100 kg N ha^-1
- C = 200 kg N ha^-1
- D = 400 kg N ha^-1
- E = 600 kg N ha^-1

### 2. 氣象資料

氣象資料來源檔案為：

- `D:\tea\202501-202512 氣象署資料.xlsx`

工作表名稱為：

- `82C160_茶改場`

工作表中含有多項逐日氣象與土壤觀測欄位，目前模型入口腳本實際映射使用的欄位為：

- `觀測時間` -> `date`
- `平均氣溫(℃)` -> `temp`
- `平均相對溼度( %)` -> `humidity`
- `平均風速(m/s)` -> `wind_out`
- `累計雨量(mm)` -> `rain`
- `平均地溫10cm(℃)` -> `soil_temp`
- `0-10cm土壤含水量(%)` -> `soil_moisture_0_10`

## 六、模型資料前處理流程

目前主管線定義於 `D:\tea\n2o_model\N2O_model_pipeline.R`，入口腳本定義於 `D:\tea\n2o_model\scripts\run_analysis.R`。資料處理流程如下：

1. 讀取五個處理檔案，保留 `date`、`treatment`、`fertilizer_N`、`N2O_flux`。
2. 讀取氣象資料並將中文欄位標準化為模型所需英文欄位。
3. 以完整日期序列補齊逐日氣象資料。
4. 建立 lag 變數：
   - `rain_lag0` 到 `rain_lag7`
   - `temp_lag1`
   - `humidity_lag1`
   - `soil_temp_lag1`
5. 將 N2O 觀測資料依 `date` 合併 lag 後氣象資料。
6. 以完整樣本計算 `rain_lag0` 到 `rain_lag7` 與 `N2O_flux` 的 Pearson 相關。
7. 使用相關係數絕對值建立加權雨量指標 `rain_weighted`。
8. 建立主模型、簡化模型與 pulse detection 流程。

## 七、rain_weighted 的定義與意義

本研究並未直接使用單日雨量，而是建立多日加權雨量指標：

`rain_weighted = Σ(rain_lag_i × weight_i)`

其中權重由 `|r_i| / Σ|r_i|` 定義，`r_i` 為各 rain lag 與 N2O_flux 的 Pearson 相關係數。這樣的設計用來反映：

1. N2O 排放對降雨可能存在延遲效應。
2. 茶園 N2O 排放常為事件驅動，而非單日即時反應。
3. 多日降雨累積比單一日降雨更能反映土壤濕潤脈衝。

目前權重結果顯示：

- `rain_lag1`：r = 0.2183，weight = 0.3048
- `rain_lag4`：r = 0.1639，weight = 0.2288
- `rain_lag0`：r = 0.1256，weight = 0.1754
- `rain_lag2`：r = 0.0882，weight = 0.1231
- `rain_lag5`：r = 0.0811，weight = 0.1132

這表示茶園 N2O 排放主要受到前 1 日、前 4 日與當日降雨之共同影響，支持短期累積降雨脈衝的概念。

## 八、目前模型架構

### 1. 主模型

主模型如下：

`N2O_flux ~ rain_weighted * fertilizer_N + soil_temp_lag1 + temp_lag1 + humidity_lag1`

此模型的解釋如下：

- `rain_weighted`：代表短期累積降雨脈衝。
- `fertilizer_N`：代表施氮量強度。
- `soil_temp_lag1`：代表前一日土壤熱環境。
- `temp_lag1`：代表前一日氣溫背景。
- `humidity_lag1`：代表前一日空氣濕度背景。
- `rain_weighted * fertilizer_N`：代表降雨與施肥量的交互作用。

### 2. 簡化模型

簡化模型如下：

`N2O_flux ~ rain_weighted * fertilizer_N + temp_lag1 + humidity_lag1`

此模型移除土壤溫度變數，用於評估在沒有土壤感測資料的情況下，是否仍可維持合理預測能力。

### 3. Pulse detection 模型

Pulse detection 以 N2O_flux 第 75 百分位作為高排放事件定義，並以 logistic regression 配合 `rain_weighted` 門檻掃描，找出高排放事件較易發生的降雨觸發值。

## 九、何謂脈衝（pulse）

在本研究中，脈衝是指 N2O 排放在短時間內突然明顯升高、之後又回落的高排放事件。其本質通常是：

1. 先有氮源供應。
2. 再遇到降雨或再濕潤事件。
3. 土壤水分升高，微生物反應加快。
4. 在短期內產生較高 N2O 排放峰值。

因此，脈衝不是日常穩定背景排放，而是由施肥與降雨共同驅動的事件型排放高峰。

## 十、目前模型主要結果

### 1. 樣本數

- 原始樣本數：505
- 有效建模樣本數：495

### 2. 主模型係數

主模型係數如下：

- `(Intercept)` = -0.009144，p = 0.6819
- `rain_weighted` = 4.018e-05，p = 0.9230
- `fertilizer_N` = 5.276e-05，p = 1.47e-04
- `soil_temp_lag1` = -0.003166，p = 0.0444
- `temp_lag1` = 0.003100，p = 0.0529
- `humidity_lag1` = 1.938e-04，p = 0.4272
- `rain_weighted:fertilizer_N` = 6.762e-06，p = 3.84e-08

### 3. 模型表現

主模型：

- R2 = 0.2396
- Adjusted R2 = 0.2302
- RMSE = 0.05434
- MAE = 0.02653
- AIC = -1462.55
- BIC = -1428.92

簡化模型：

- R2 = 0.2332
- Adjusted R2 = 0.2254
- RMSE = 0.05457
- MAE = 0.02647
- AIC = -1460.45
- BIC = -1431.02

### 4. Pulse threshold

最佳降雨觸發門檻為：

- `rain_weighted = 4.4078`

對應分類表現為：

- sensitivity = 0.6532
- specificity = 0.6927
- Youden = 0.3459
- TP = 81
- TN = 257
- FP = 114
- FN = 43

## 十一、結果詮釋

目前模型結果支持以下幾個重要結論：

1. `fertilizer_N` 為顯著正向因子，表示施氮量提高會增加 N2O 排放基礎風險。
2. `rain_weighted` 單獨主效應不顯著，表示降雨不是單獨驅動因子。
3. `rain_weighted:fertilizer_N` 高度顯著，表示降雨在高施氮條件下會顯著放大 N2O 排放。
4. 茶園 N2O 排放具有明顯之降雨脈衝特性。
5. 簡化模型與主模型表現接近，表示即使缺少土壤感測資料，模型仍具有一定管理應用性。

換句話說，雨量在本系統中的角色較接近 trigger，而施肥量則是 amplifier。

## 十二、模型與田間研究之連結

目前的田間研究顯示：

- 有機茶園 N2O 排放高於慣行茶園。
- 有機茶園土壤有機碳高於慣行茶園。

而目前建立的預測模型則進一步補充了「茶園 N2O 為何會升高」的機制性說明，即：

1. 高氮供應增加了排放風險。
2. 降雨事件本身不足以單獨造成高排放。
3. 當高施肥條件與降雨脈衝重疊時，更容易形成 N2O 高排放事件。

因此，模型結果可用來支撐田間觀測結果，並延伸至施肥管理與氣象風險預警。

## 十三、目前輸出檔案位置

### 1. 主表格

- `D:\tea\n2o_model\outputs\tables\Table_01_final_model_coefficients.csv`
- `D:\tea\n2o_model\outputs\tables\Table_02_simple_model_coefficients.csv`
- `D:\tea\n2o_model\outputs\tables\Table_03_model_comparison.csv`
- `D:\tea\n2o_model\outputs\tables\Table_04_best_trigger_threshold.csv`
- `D:\tea\n2o_model\outputs\tables\Table_S1_rain_lag_weights.csv`

### 2. 圖形

- `D:\tea\n2o_model\outputs\figures\Figure_01_final_lm_obs_vs_pred.png`
- `D:\tea\n2o_model\outputs\figures\Figure_01_final_lm_residuals.png`
- `D:\tea\n2o_model\outputs\figures\Figure_01_final_lm_rain_vs_n2o.png`
- `D:\tea\n2o_model\outputs\figures\Figure_03_final_lm_monthly_heatmap.png`
- `D:\tea\n2o_model\outputs\figures\Figure_04_pulse_q75_pulse_prob.png`
- `D:\tea\n2o_model\outputs\figures\Figure_04_pulse_q75_youden_scan.png`

### 3. 補充說明文件

- `D:\tea\n2o_model\docs\RESULTS_DRAFT_zh.md`
- `D:\tea\n2o_model\N2O_model_report_zh.md`
- `D:\tea\n2o_model\docs\MODEL_RESEARCH_SUMMARY_zh.md`

## 十四、研究限制

目前模型仍有以下限制：

1. R2 約為 0.24，表示仍有相當比例變異未被解釋。
2. 尚未納入土壤 NH4+、NO3-、溶解性有機碳、WFPS 等重要變數。
3. 目前主要為線性模型，可能低估非線性與極端脈衝現象。
4. 目前以處理資料建模，尚未直接把有機與慣行栽培制度作為制度變數納入。

## 十五、下一步建議

後續最值得優先推進的方向包括：

1. 將有機與慣行栽培模式納入模型，直接比較制度效應。
2. 加入土壤無機氮與土壤含水狀態，提升解釋力。
3. 以目前模型為核心，建立施肥避雨管理建議與高風險日預警框架。
4. 將 N2O 碳排與土壤有機碳碳匯整合為完整碳收支模型。
