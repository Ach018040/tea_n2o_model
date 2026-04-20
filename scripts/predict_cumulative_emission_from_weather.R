required_packages <- c("dplyr", "readxl", "readr", "tidyr")
missing_packages <- required_packages[!(required_packages %in% rownames(installed.packages()))]
if (length(missing_packages) > 0) {
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}

invisible(lapply(required_packages, library, character.only = TRUE))

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------

weather_path <- "../weather_2026_converted.xlsx"
weather_sheet <- 1

coefficients_path <- "outputs/tables/Table_02_simple_model_coefficients.csv"
weights_path <- "outputs/tables/Table_S1_rain_lag_weights.csv"
out_dir <- "outputs/predicted_emission_2026"

treatment_levels <- tibble::tribble(
  ~treatment, ~fertilizer_N,
  "A", 0,
  "B", 100,
  "C", 200,
  "D", 400,
  "E", 600
)

# Best-fit interpretation from the field master workbook:
# N2O_flux behaves as kg N2O-N ha^-1 day^-1, because the same values are
# integrated directly into cumulative N2O-N kg/ha totals.
flux_unit <- "kg_N2O_N_ha_d"

# Set negative predictions to zero before integration.
clamp_negative_flux_to_zero <- TRUE

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

read_weather_table <- function(path, sheet = 1) {
  if (!file.exists(path)) {
    stop(sprintf("Missing weather file: %s", path))
  }

  readxl::read_excel(path, sheet = sheet) %>%
    dplyr::rename(
      date = date,
      temp = temp,
      humidity = humidity,
      rain = rain
    ) %>%
    dplyr::mutate(
      date = as.Date(date),
      temp = as.numeric(temp),
      humidity = as.numeric(humidity),
      rain = as.numeric(rain)
    ) %>%
    dplyr::arrange(date)
}

make_weather_features <- function(weather_df, rain_weights) {
  df <- weather_df %>%
    dplyr::arrange(date) %>%
    dplyr::mutate(
      rain_lag0 = rain,
      rain_lag1 = dplyr::lag(rain, 1),
      rain_lag2 = dplyr::lag(rain, 2),
      rain_lag3 = dplyr::lag(rain, 3),
      rain_lag4 = dplyr::lag(rain, 4),
      rain_lag5 = dplyr::lag(rain, 5),
      rain_lag6 = dplyr::lag(rain, 6),
      rain_lag7 = dplyr::lag(rain, 7),
      temp_lag1 = dplyr::lag(temp, 1),
      humidity_lag1 = dplyr::lag(humidity, 1)
    )

  df$rain_weighted <- 0
  for (i in seq_len(nrow(rain_weights))) {
    lag_name <- rain_weights$variable[i]
    weight <- rain_weights$weight[i]
    df$rain_weighted <- df$rain_weighted + dplyr::coalesce(df[[lag_name]], 0) * weight
  }

  df
}

make_prediction_table <- function(feature_df, treatment_df, coefs) {
  model_df <- tidyr::crossing(
    feature_df,
    treatment_df
  ) %>%
    dplyr::mutate(
      pred_flux =
        coefs["(Intercept)"] +
        coefs["rain_weighted"] * rain_weighted +
        coefs["fertilizer_N"] * fertilizer_N +
        coefs["temp_lag1"] * temp_lag1 +
        coefs["humidity_lag1"] * humidity_lag1 +
        coefs["rain_weighted:fertilizer_N"] * rain_weighted * fertilizer_N
    )

  if (clamp_negative_flux_to_zero) {
    model_df <- model_df %>%
      dplyr::mutate(pred_flux = pmax(pred_flux, 0))
  }

  model_df
}

integrate_emission <- function(pred_df, flux_unit) {
  pred_df %>%
    dplyr::arrange(treatment, date) %>%
    dplyr::group_by(treatment, fertilizer_N) %>%
    dplyr::mutate(
      next_date = dplyr::lead(date),
      next_flux = dplyr::lead(pred_flux),
      dt_days = as.numeric(next_date - date),
      dt_hours = dt_days * 24,
      cumulative_mass_m2 = dplyr::case_when(
        flux_unit == "kg_N2O_N_ha_d" ~ ((pred_flux + next_flux) / 2) * dt_days,
        flux_unit == "mg_N_m2_h" ~ ((pred_flux + next_flux) / 2) * dt_hours,
        flux_unit == "mg_N_m2_d" ~ ((pred_flux + next_flux) / 2) * dt_days,
        flux_unit == "ug_N_m2_h" ~ (((pred_flux + next_flux) / 2) * dt_hours) / 1000,
        TRUE ~ NA_real_
      )
    ) %>%
    dplyr::summarise(
      prediction_days = dplyr::n(),
      integration_days = sum(dt_days, na.rm = TRUE),
      cumulative_model_total = sum(cumulative_mass_m2, na.rm = TRUE),
      cumulative_kg_N_ha = dplyr::case_when(
        flux_unit == "kg_N2O_N_ha_d" ~ cumulative_model_total,
        TRUE ~ cumulative_model_total * 0.01
      ),
      cumulative_kg_N2O_N_ha = cumulative_kg_N_ha,
      cumulative_kg_N2O_ha = cumulative_kg_N_ha * 44 / 28,
      .groups = "drop"
    )
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------

if (!flux_unit %in% c("kg_N2O_N_ha_d", "mg_N_m2_h", "mg_N_m2_d", "ug_N_m2_h")) {
  stop("flux_unit must be one of: kg_N2O_N_ha_d, mg_N_m2_h, mg_N_m2_d, ug_N_m2_h")
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

weather_df <- read_weather_table(weather_path, weather_sheet)
weights_df <- readr::read_csv(weights_path, show_col_types = FALSE) %>%
  dplyr::select(variable, weight)
coef_table <- readr::read_csv(coefficients_path, show_col_types = FALSE)
coef_values <- stats::setNames(coef_table$estimate, coef_table$term)

required_terms <- c(
  "(Intercept)",
  "rain_weighted",
  "fertilizer_N",
  "temp_lag1",
  "humidity_lag1",
  "rain_weighted:fertilizer_N"
)

missing_terms <- setdiff(required_terms, names(coef_values))
if (length(missing_terms) > 0) {
  stop(sprintf("Missing model coefficients: %s", paste(missing_terms, collapse = ", ")))
}

feature_df <- make_weather_features(weather_df, weights_df)

prediction_df <- make_prediction_table(
  feature_df = feature_df,
  treatment_df = treatment_levels,
  coefs = coef_values
)

summary_df <- integrate_emission(
  pred_df = prediction_df,
  flux_unit = flux_unit
)

meta_note <- sprintf(
  "Assumed flux unit: %s | Model: simple model using rain_weighted + temp_lag1 + humidity_lag1",
  flux_unit
)

readr::write_csv(prediction_df, file.path(out_dir, "daily_predicted_flux_2026.csv"))
readr::write_csv(summary_df, file.path(out_dir, "cumulative_emission_summary_2026.csv"))
writeLines(meta_note, con = file.path(out_dir, "README.txt"))

cat(meta_note, "\n\n")
print(summary_df)
