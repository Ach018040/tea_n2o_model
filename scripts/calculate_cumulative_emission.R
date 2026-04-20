library(dplyr)

# Calculate cumulative N2O emission from repeated flux observations.
# For the current tea datasets, the most consistent interpretation is:
# - N2O_flux is kg N2O-N ha^-1 day^-1
# because the field master workbook integrates the same values directly into
# cumulative N2O-N kg/ha totals.
calculate_cumulative_emission <- function(
  df,
  date_col = "date",
  treatment_col = "treatment",
  flux_col = "N2O_flux",
  flux_unit = c("kg_N2O_N_ha_d", "ug_N_m2_h", "mg_N_m2_d")
) {
  flux_unit <- match.arg(flux_unit)

  required_cols <- c(date_col, treatment_col, flux_col)
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  data <- df %>%
    mutate(
      .date = as.Date(.data[[date_col]]),
      .treatment = .data[[treatment_col]],
      .flux_raw = as.numeric(.data[[flux_col]])
    ) %>%
    arrange(.treatment, .date) %>%
    group_by(.treatment) %>%
    mutate(
      dt_days = as.numeric(lead(.date) - .date),
      dt_hours = dt_days * 24,
      flux_next_raw = lead(.flux_raw)
    )

  if (flux_unit == "kg_N2O_N_ha_d") {
    data <- data %>%
      mutate(
        trapezoid_kg_N_ha = (.flux_raw + flux_next_raw) / 2 * dt_days,
        cumulative_base = trapezoid_kg_N_ha
      )

    summary <- data %>%
      summarise(
        cumulative_kg_N_ha = sum(cumulative_base, na.rm = TRUE),
        cumulative_kg_N2O_N_ha = cumulative_kg_N_ha,
        cumulative_kg_N2O_ha = cumulative_kg_N_ha * 44 / 28,
        .groups = "drop"
      )
  } else if (flux_unit == "ug_N_m2_h") {
    data <- data %>%
      mutate(
        trapezoid_ug_N_m2 = (.flux_raw + flux_next_raw) / 2 * dt_hours,
        cumulative_base = trapezoid_ug_N_m2
      )

    summary <- data %>%
      summarise(
        cumulative_ug_N_m2 = sum(cumulative_base, na.rm = TRUE),
        cumulative_kg_N_ha = cumulative_ug_N_m2 * 1e-5,
        cumulative_kg_N2O_ha = cumulative_kg_N_ha * 44 / 28,
        .groups = "drop"
      )
  } else {
    data <- data %>%
      mutate(
        trapezoid_mg_N_m2 = (.flux_raw + flux_next_raw) / 2 * dt_days,
        cumulative_base = trapezoid_mg_N_m2
      )

    summary <- data %>%
      summarise(
        cumulative_mg_N_m2 = sum(cumulative_base, na.rm = TRUE),
        cumulative_kg_N_ha = cumulative_mg_N_m2 * 0.01,
        cumulative_kg_N2O_ha = cumulative_kg_N_ha * 44 / 28,
        .groups = "drop"
      )
  }

  list(
    intervals = data,
    summary = summary
  )
}

# Example:
# df <- read.csv("your_flux_data.csv")
# result <- calculate_cumulative_emission(
#   df,
#   date_col = "date",
#   treatment_col = "treatment",
#   flux_col = "N2O_flux",
#   flux_unit = "kg_N2O_N_ha_d"
# )
# print(result$summary)
