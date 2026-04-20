suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(readr)
  library(broom)
})

set.seed(123)

# Prepare complete daily weather data and standardize column names.
prep_weather_daily <- function(weather_raw,
                               date_col = "date",
                               rain_col = "rain",
                               temp_col = "temp",
                               humid_col = "humidity",
                               soiltemp_col = "soil_temp") {
  df <- weather_raw %>%
    rename(date = all_of(date_col)) %>%
    mutate(date = as.Date(date)) %>%
    arrange(date)

  for (nm in c(rain_col, temp_col, humid_col, soiltemp_col)) {
    if (nm %in% names(df)) {
      df[[nm]] <- suppressWarnings(as.numeric(df[[nm]]))
    }
  }

  full_dates <- tibble(
    date = seq.Date(min(df$date, na.rm = TRUE), max(df$date, na.rm = TRUE), by = "day")
  )

  df_full <- full_dates %>%
    left_join(df, by = "date") %>%
    arrange(date)

  if (rain_col %in% names(df_full)) df_full <- df_full %>% rename(rain = all_of(rain_col))
  if (temp_col %in% names(df_full)) df_full <- df_full %>% rename(temp = all_of(temp_col))
  if (humid_col %in% names(df_full)) df_full <- df_full %>% rename(humidity = all_of(humid_col))
  if (soiltemp_col %in% names(df_full)) df_full <- df_full %>% rename(soil_temp = all_of(soiltemp_col))

  df_full
}

# Build lagged weather features.
make_lags <- function(weather_daily) {
  weather_daily %>%
    arrange(date) %>%
    mutate(
      rain_lag0 = rain,
      rain_lag1 = dplyr::lag(rain, 1),
      rain_lag2 = dplyr::lag(rain, 2),
      rain_lag3 = dplyr::lag(rain, 3),
      rain_lag4 = dplyr::lag(rain, 4),
      rain_lag5 = dplyr::lag(rain, 5),
      rain_lag6 = dplyr::lag(rain, 6),
      rain_lag7 = dplyr::lag(rain, 7),
      temp_lag1 = dplyr::lag(temp, 1),
      humidity_lag1 = dplyr::lag(humidity, 1),
      soil_temp_lag1 = if ("soil_temp" %in% names(.)) dplyr::lag(soil_temp, 1) else NA_real_
    )
}

# Merge N2O observations with lagged weather features.
merge_n2o_weather <- function(n2o_df, weather_lagged) {
  n2o_df %>%
    mutate(
      date = as.Date(date),
      N2O_flux = suppressWarnings(as.numeric(N2O_flux)),
      fertilizer_N = suppressWarnings(as.numeric(fertilizer_N))
    ) %>%
    left_join(weather_lagged, by = "date")
}

# Estimate Pearson-based rainfall weights.
calc_rain_weights <- function(train_df, rain_lag_vars = paste0("rain_lag", 0:7)) {
  rain_lag_vars <- rain_lag_vars[rain_lag_vars %in% names(train_df)]

  results <- lapply(rain_lag_vars, function(v) {
    tmp <- train_df %>% select(N2O_flux, all_of(v)) %>% na.omit()
    if (nrow(tmp) < 10) return(NULL)
    test <- cor.test(tmp$N2O_flux, tmp[[v]], method = "pearson")
    tibble(
      variable = v,
      correlation = unname(test$estimate),
      p_value = test$p.value,
      abs_r = abs(unname(test$estimate))
    )
  })

  bind_rows(results) %>%
    mutate(weight = abs_r / sum(abs_r, na.rm = TRUE)) %>%
    arrange(desc(weight))
}

# Add weighted rainfall index.
add_rain_weighted <- function(df, rain_cor) {
  df2 <- df
  df2$rain_weighted <- 0

  for (i in seq_len(nrow(rain_cor))) {
    v <- rain_cor$variable[i]
    w <- rain_cor$weight[i]
    df2$rain_weighted <- df2$rain_weighted + df2[[v]] * w
  }

  df2
}

# Fit the main and simplified linear models.
fit_models <- function(train_df) {
  final_model <- lm(
    N2O_flux ~ rain_weighted * fertilizer_N +
      soil_temp_lag1 + temp_lag1 + humidity_lag1,
    data = train_df
  )

  simple_model <- lm(
    N2O_flux ~ rain_weighted * fertilizer_N +
      temp_lag1 + humidity_lag1,
    data = train_df
  )

  list(final_model = final_model, simple_model = simple_model)
}

# Collect common model metrics.
calc_metrics_lm <- function(model, df, model_name) {
  pred <- predict(model, newdata = df)
  obs <- df$N2O_flux

  tibble(
    model_name = model_name,
    n = nrow(df),
    r2 = summary(model)$r.squared,
    adjr2 = summary(model)$adj.r.squared,
    rmse = sqrt(mean((obs - pred)^2, na.rm = TRUE)),
    mae = mean(abs(obs - pred), na.rm = TRUE),
    aic = AIC(model),
    bic = BIC(model)
  )
}

format_coefficient_table <- function(model) {
  broom::tidy(model) %>%
    transmute(
      term = term,
      estimate = estimate,
      std_error = std.error,
      statistic = statistic,
      p_value = p.value,
      significance = case_when(
        p.value < 0.001 ~ "***",
        p.value < 0.01 ~ "**",
        p.value < 0.05 ~ "*",
        p.value < 0.1 ~ ".",
        TRUE ~ ""
      )
    )
}

# Plot diagnostics for a fitted linear model.
plot_diagnostics <- function(model, df, figure_dir, prefix) {
  df2 <- df %>%
    mutate(
      pred = predict(model, newdata = df),
      resid = N2O_flux - pred
    )

  p1 <- ggplot(df2, aes(x = N2O_flux, y = pred)) +
    geom_point(alpha = 0.6) +
    geom_abline(slope = 1, intercept = 0) +
    theme_minimal(base_size = 12) +
    labs(title = paste(prefix, "Observed vs Predicted"), x = "Observed", y = "Predicted")

  p2 <- ggplot(df2, aes(x = pred, y = resid)) +
    geom_point(alpha = 0.6) +
    geom_hline(yintercept = 0) +
    theme_minimal(base_size = 12) +
    labs(title = paste(prefix, "Residuals vs Fitted"), x = "Predicted", y = "Residual")

  p3 <- ggplot(df2, aes(x = rain_weighted, y = N2O_flux, color = factor(fertilizer_N))) +
    geom_point(alpha = 0.5) +
    geom_smooth(method = "lm", se = FALSE) +
    theme_minimal(base_size = 12) +
    labs(
      title = paste(prefix, "rain_weighted vs N2O"),
      x = "rain_weighted",
      y = "N2O_flux",
      color = "fertilizer_N"
    )

  ggsave(file.path(figure_dir, paste0(prefix, "_obs_vs_pred.png")), p1, width = 7, height = 5, dpi = 300)
  ggsave(file.path(figure_dir, paste0(prefix, "_residuals.png")), p2, width = 7, height = 5, dpi = 300)
  ggsave(file.path(figure_dir, paste0(prefix, "_rain_vs_n2o.png")), p3, width = 7, height = 5, dpi = 300)

  invisible(list(obs_pred = p1, residuals = p2, rain = p3))
}

# Predict daily annual N2O under fixed fertilizer scenarios.
predict_annual_daily <- function(weather_lagged, rain_cor, model,
                                 fert_levels = c(0, 100, 200, 400, 600)) {
  daily <- weather_lagged %>%
    select(date, starts_with("rain_lag"), temp_lag1, humidity_lag1, soil_temp_lag1) %>%
    arrange(date) %>%
    na.omit()

  daily <- add_rain_weighted(daily, rain_cor)

  scenario <- tidyr::crossing(
    date = daily$date,
    fertilizer_N = fert_levels
  ) %>%
    left_join(daily, by = "date") %>%
    arrange(date, fertilizer_N)

  scenario$predicted_N2O <- predict(model, newdata = scenario)

  scenario %>%
    mutate(
      month = format(date, "%m"),
      doy = as.integer(format(date, "%j"))
    )
}

# Plot monthly heatmap for annual predictions.
plot_monthly_heatmap <- function(scenario_df, figure_dir, prefix) {
  monthly <- scenario_df %>%
    group_by(month, fertilizer_N) %>%
    summarise(mean_pred = mean(predicted_N2O, na.rm = TRUE), .groups = "drop")

  p <- ggplot(monthly, aes(x = month, y = factor(fertilizer_N), fill = mean_pred)) +
    geom_tile() +
    theme_minimal(base_size = 12) +
    labs(
      title = paste(prefix, "Monthly mean predicted N2O"),
      x = "Month",
      y = "Fertilizer N",
      fill = "Mean N2O"
    )

  ggsave(file.path(figure_dir, paste0(prefix, "_monthly_heatmap.png")), p, width = 8, height = 5, dpi = 300)
  invisible(p)
}

# Build pulse labels from a quantile or mean + SD definition.
fit_pulse_model <- function(df, pulse_def = c("q75", "mean1sd")) {
  pulse_def <- match.arg(pulse_def)

  threshold <- if (pulse_def == "q75") {
    quantile(df$N2O_flux, 0.75, na.rm = TRUE)
  } else {
    mean(df$N2O_flux, na.rm = TRUE) + sd(df$N2O_flux, na.rm = TRUE)
  }

  df2 <- df %>%
    mutate(pulse = ifelse(N2O_flux >= threshold, 1, 0))

  pulse_model <- glm(
    pulse ~ rain_weighted * fertilizer_N + soil_temp_lag1 + temp_lag1 + humidity_lag1,
    data = df2,
    family = binomial(link = "logit")
  )

  df2$pulse_prob <- predict(pulse_model, type = "response")

  list(model = pulse_model, data = df2, threshold = threshold)
}

# Scan a rainfall threshold using Youden index.
scan_trigger_threshold_youden <- function(pulse_df, rain_var = "rain_weighted", n_grid = 200) {
  x <- pulse_df[[rain_var]]
  y <- pulse_df$pulse
  grid <- seq(min(x, na.rm = TRUE), max(x, na.rm = TRUE), length.out = n_grid)

  scan <- lapply(grid, function(th) {
    pred <- ifelse(x >= th, 1, 0)
    tp <- sum(pred == 1 & y == 1, na.rm = TRUE)
    tn <- sum(pred == 0 & y == 0, na.rm = TRUE)
    fp <- sum(pred == 1 & y == 0, na.rm = TRUE)
    fn <- sum(pred == 0 & y == 1, na.rm = TRUE)

    sensitivity <- ifelse((tp + fn) > 0, tp / (tp + fn), NA_real_)
    specificity <- ifelse((tn + fp) > 0, tn / (tn + fp), NA_real_)
    youden <- sensitivity + specificity - 1

    tibble(
      threshold = th,
      sensitivity = sensitivity,
      specificity = specificity,
      youden = youden,
      TP = tp,
      TN = tn,
      FP = fp,
      FN = fn
    )
  }) %>% bind_rows()

  best <- scan %>%
    filter(youden == max(youden, na.rm = TRUE)) %>%
    slice(1)

  list(scan = scan, best = best)
}

# Plot pulse probability and threshold scan.
plot_pulse_outputs <- function(pulse_df, scan_res, figure_dir, prefix) {
  best_th <- scan_res$best$threshold

  p1 <- ggplot(pulse_df, aes(x = rain_weighted, y = pulse_prob, color = factor(fertilizer_N))) +
    geom_point(alpha = 0.4) +
    theme_minimal(base_size = 12) +
    labs(
      title = paste(prefix, "Pulse probability"),
      x = "rain_weighted",
      y = "Predicted pulse probability",
      color = "fertilizer_N"
    )

  p2 <- ggplot(scan_res$scan, aes(x = threshold, y = youden)) +
    geom_line() +
    geom_vline(xintercept = best_th, linetype = "dashed") +
    theme_minimal(base_size = 12) +
    labs(
      title = paste(prefix, "Youden threshold scan"),
      x = "rain_weighted threshold",
      y = "Youden"
    )

  ggsave(file.path(figure_dir, paste0(prefix, "_pulse_prob.png")), p1, width = 7, height = 5, dpi = 300)
  ggsave(file.path(figure_dir, paste0(prefix, "_youden_scan.png")), p2, width = 7, height = 5, dpi = 300)
}

make_output_dirs <- function(out_dir) {
  figure_dir <- file.path(out_dir, "figures")
  table_dir <- file.path(out_dir, "tables")
  dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  list(figure_dir = figure_dir, table_dir = table_dir)
}

# Full pipeline runner.
run_all <- function(n2o_df, weather_raw, out_dir = "N2O_model_outputs") {
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  output_dirs <- make_output_dirs(out_dir)
  figure_dir <- output_dirs$figure_dir
  table_dir <- output_dirs$table_dir

  weather_daily <- prep_weather_daily(weather_raw)
  weather_lagged <- make_lags(weather_daily)
  merged <- merge_n2o_weather(n2o_df, weather_lagged)

  needed <- c(
    "N2O_flux", "fertilizer_N",
    paste0("rain_lag", 0:7),
    "temp_lag1", "humidity_lag1", "soil_temp_lag1"
  )
  needed <- needed[needed %in% names(merged)]

  train <- merged %>%
    select(all_of(needed)) %>%
    na.omit()

  rain_cor <- calc_rain_weights(train)
  train <- add_rain_weighted(train, rain_cor)

  models <- fit_models(train)
  coef_final <- format_coefficient_table(models$final_model)
  coef_simple <- format_coefficient_table(models$simple_model)

  write_csv(rain_cor, file.path(table_dir, "Table_S1_rain_lag_weights.csv"))
  write_csv(coef_final, file.path(table_dir, "Table_01_final_model_coefficients.csv"))
  write_csv(coef_simple, file.path(table_dir, "Table_02_simple_model_coefficients.csv"))

  model_comparison <- bind_rows(
    calc_metrics_lm(models$final_model, train, "final_lm"),
    calc_metrics_lm(models$simple_model, train, "simple_lm")
  )
  write_csv(model_comparison, file.path(table_dir, "Table_03_model_comparison.csv"))

  plot_diagnostics(models$final_model, train, figure_dir, "Figure_01_final_lm")
  plot_diagnostics(models$simple_model, train, figure_dir, "Figure_02_simple_lm")

  scenario <- predict_annual_daily(weather_lagged, rain_cor, models$final_model)
  write_csv(scenario, file.path(table_dir, "Table_S2_annual_daily_predictions.csv"))
  plot_monthly_heatmap(scenario, figure_dir, "Figure_03_final_lm")

  pulse_res <- fit_pulse_model(train, pulse_def = "q75")
  write_csv(pulse_res$data, file.path(table_dir, "Table_S3_pulse_dataset_q75.csv"))
  capture.output(summary(pulse_res$model), file = file.path(table_dir, "Appendix_S1_pulse_glm_summary.txt"))

  scan_res <- scan_trigger_threshold_youden(pulse_res$data)
  write_csv(scan_res$scan, file.path(table_dir, "Table_S4_youden_scan_results.csv"))
  write_csv(scan_res$best, file.path(table_dir, "Table_04_best_trigger_threshold.csv"))
  plot_pulse_outputs(pulse_res$data, scan_res, figure_dir, "Figure_04_pulse_q75")

  capture.output(summary(models$final_model), file = file.path(table_dir, "Appendix_S2_final_model_summary.txt"))
  capture.output(summary(models$simple_model), file = file.path(table_dir, "Appendix_S3_simple_model_summary.txt"))
  capture.output(sessionInfo(), file = file.path(table_dir, "Appendix_S4_sessionInfo.txt"))

  invisible(
    list(
      train = train,
      rain_cor = rain_cor,
      final_model = models$final_model,
      simple_model = models$simple_model,
      coef_final = coef_final,
      coef_simple = coef_simple,
      model_comparison = model_comparison,
      scenario = scenario,
      pulse_model = pulse_res$model,
      best_threshold = scan_res$best
    )
  )
}

# Example usage:
# n2o_df <- read_csv("N2O_all_treatments.csv")
# weather_raw <- read_csv("daily_weather_365days.csv")
# results <- run_all(n2o_df, weather_raw, out_dir = "N2O_model_outputs")
