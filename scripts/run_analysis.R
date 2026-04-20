required_packages <- c(
  "dplyr",
  "tidyr",
  "ggplot2",
  "readr",
  "readxl",
  "broom"
)

missing_packages <- required_packages[!(required_packages %in% rownames(installed.packages()))]
if (length(missing_packages) > 0) {
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}

invisible(lapply(required_packages, library, character.only = TRUE))

source("N2O_model_pipeline.R")

input_config <- list(
  n2o_files = list(
    list(path = "../0311_A.xlsx", sheet = 1, treatment = "A", fertilizer_N = 0),
    list(path = "../0311_B.xlsx", sheet = 1, treatment = "B", fertilizer_N = 100),
    list(path = "../0311_C.xlsx", sheet = 1, treatment = "C", fertilizer_N = 200),
    list(path = "../0311_D.xlsx", sheet = 1, treatment = "D", fertilizer_N = 400),
    list(path = "../0311_E.xlsx", sheet = 1, treatment = "E", fertilizer_N = 600)
  ),
  weather = list(
    path = "../202501-202512 氣象署資料.xlsx",
    sheet = 1
  )
)

read_input_table <- function(path, sheet = NULL) {
  if (!file.exists(path)) {
    stop(sprintf("Missing input file: %s", path))
  }

  extension <- tolower(tools::file_ext(path))

  if (extension == "csv") {
    return(readr::read_csv(path, show_col_types = FALSE))
  }

  if (extension %in% c("xlsx", "xls")) {
    return(readxl::read_excel(path, sheet = sheet))
  }

  stop(sprintf("Unsupported file type: %s", path))
}

read_treatment_table <- function(path, sheet, treatment, fertilizer_N) {
  df <- read_input_table(path = path, sheet = sheet)

  if (!all(c("date", "N2O_flux") %in% names(df))) {
    stop(sprintf("Treatment file is missing required columns: %s", path))
  }

  df %>%
    dplyr::mutate(
      treatment = treatment,
      fertilizer_N = fertilizer_N
    ) %>%
    dplyr::select(date, treatment, fertilizer_N, N2O_flux)
}

standardize_weather_table <- function(df) {
  weather_map <- c(
    "觀測時間" = "date",
    "平均氣溫(℃)" = "temp",
    "平均相對溼度( %)" = "humidity",
    "平均風速(m/s)" = "wind_out",
    "累計雨量(mm)" = "rain",
    "平均地溫10cm(℃)" = "soil_temp",
    "0-10cm土壤含水量(%)" = "soil_moisture_0_10"
  )

  matched <- intersect(names(weather_map), names(df))
  renamed <- df %>% dplyr::rename(!!!setNames(matched, weather_map[matched]))

  required_weather <- c("date", "temp", "humidity", "rain", "soil_temp")
  missing_required <- setdiff(required_weather, names(renamed))
  if (length(missing_required) > 0) {
    stop(
      sprintf(
        "Weather file is missing required columns after rename: %s",
        paste(missing_required, collapse = ", ")
      )
    )
  }

  renamed %>%
    dplyr::mutate(date = as.Date(date)) %>%
    dplyr::arrange(date)
}

n2o_df <- dplyr::bind_rows(lapply(input_config$n2o_files, function(cfg) {
  read_treatment_table(
    path = cfg$path,
    sheet = cfg$sheet,
    treatment = cfg$treatment,
    fertilizer_N = cfg$fertilizer_N
  )
}))

weather_raw <- standardize_weather_table(read_input_table(
  path = input_config$weather$path,
  sheet = input_config$weather$sheet
))

results <- run_all(
  n2o_df = n2o_df,
  weather_raw = weather_raw,
  out_dir = "outputs"
)

print(results$model_comparison)
print(results$best_threshold)
