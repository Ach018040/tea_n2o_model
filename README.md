# N2O Model Project

This RStudio project organizes the N2O emission modeling workflow into a clean local structure.

## Folders

- `data/raw/`: original observation and weather files
- `data/processed/`: intermediate cleaned datasets
- `outputs/figures/`: exported plots
- `outputs/tables/`: exported tables
- `scripts/`: runner scripts and future helpers
- `docs/`: manuscript-facing notes and supporting text

## Key files

- `N2O_model_pipeline.R`: main reproducible modeling pipeline
- `N2O_model_report_zh.md`: manuscript-ready Chinese writeup
- `docs/RESULTS_DRAFT_zh.md`: results section grounded in the latest model outputs
- `scripts/run_analysis.R`: entry script for local execution

## Current data wiring

The project is currently wired to:

- `D:\tea\0311_A.xlsx`
- `D:\tea\0311_B.xlsx`
- `D:\tea\0311_C.xlsx`
- `D:\tea\0311_D.xlsx`
- `D:\tea\0311_E.xlsx`
- `D:\tea\202501-202512 氣象署資料.xlsx`

If you replace the source files later, update the paths inside `scripts/run_analysis.R`.

## Suggested workflow

1. Open `D:\tea\n2o_model\N2O-model.Rproj` in RStudio.
2. Run `D:\tea\n2o_model\scripts\run_analysis.R`.
3. Review exported tables in `D:\tea\n2o_model\outputs\tables\`.
4. Review exported figures in `D:\tea\n2o_model\outputs\figures\`.
5. Use `D:\tea\n2o_model\docs\RESULTS_DRAFT_zh.md` as the starting point for the manuscript Results section.

## GitHub Pages deployment for the tea tool

This workspace now includes a standalone `index.html` for the tea N2O risk tool.

Recommended quick publish flow:

1. Create a new GitHub repository, for example `tea-n2o-tool`.
2. Upload `index.html` from this workspace root.
3. In GitHub, open `Settings` -> `Pages`.
4. Set `Source` to `Deploy from a branch`.
5. Choose the `main` branch and `/ (root)` folder, then save.

After GitHub Pages finishes building, the site URL will look like:

- `https://Ach018040.github.io/tea-n2o-tool/`

## Publication outputs

The pipeline writes manuscript-style outputs into:

- `outputs/tables/`
- `outputs/figures/`

Example files:

- `Table_01_final_model_coefficients.csv`
- `Table_03_model_comparison.csv`
- `Table_04_best_trigger_threshold.csv`
- `Figure_01_final_lm_obs_vs_pred.png`
- `Figure_03_final_lm_monthly_heatmap.png`
- `Figure_04_pulse_q75_youden_scan.png`
