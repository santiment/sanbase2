defmodule Sanbase.Repo.Migrations.FillStabilizationRegistryData do
  use Ecto.Migration

  def up do
    data = get_data()

    Enum.each(data, fn {metric, {stabilization_period, can_mutate}} ->
      with {:ok, registry} <- Sanbase.Metric.Registry.by_name(metric) do
        registry
        |> Sanbase.Metric.Registry.changeset(%{
          stabilization_period: stabilization_period,
          can_mutate: can_mutate
        })
        # So we don't change the updated_at, otherwise we'll have a lot of records
        # that will show that they were recently updated, but there would be nothing in the
        # metric registry changelog.
        # Doing it via the metric registry change request + sync will be much more work
        |> Ecto.Changeset.force_change(:updated_at, registry.updated_at)
        |> Sanbase.Repo.update!()
      end
    end)
  end

  def down do
    :ok
  end

  defp get_data() do
    csv_data()
    |> String.split("\n", trim: true)
    |> Enum.map(&String.split(&1, ","))
    |> Map.new(fn [metric, stabilization_period, can_mutate] ->
      can_mutate =
        case can_mutate do
          "YES" -> true
          "NO" -> false
          _ -> nil
        end

      stabilization_period =
        if Sanbase.DateTimeUtils.valid_compound_duration?(stabilization_period),
          do: stabilization_period,
          else: nil

      {metric, {stabilization_period, can_mutate}}
    end)
  end

  defp csv_data() do
    """
    active_addresses_1h,12h,NO
    active_addresses_24h,12h,NO
    active_deposits_5m,12h,NO
    active_withdrawals_5m,12h,NO
    age_destroyed,12h,NO
    community_messages_count_total,—,—
    community_messages_count_telegram,—,—
    dev_activity,3h,YES
    dev_activity_1d,,YES
    dev_activity_contributors_count,3h,
    github_activity,3h,YES
    github_activity_1d,,YES
    github_activity_contributors_count,3h,YES
    exchange_balance_per_exchange,12h,YES
    exchange_inflow_per_exchange,12h,YES
    exchange_outflow_per_exchange,12h,YES
    mvrv_usd_intraday,12h,NO
    mvrv_usd_intraday_1d,12h,NO
    mvrv_usd_intraday_30d,12h,NO
    mvrv_usd_intraday_365d,12h,NO
    mvrv_usd_intraday_2y,12h,NO
    mvrv_usd_intraday_5y,12h,NO
    mvrv_usd_intraday_10y,12h,NO
    nvt_5min,12h,NO
    sentiment_positive_total,12h,YES
    sentiment_negative_total,12h,YES
    unique_social_volume_total_5m,12h,YES
    unique_social_volume_twitter_5m,12h,YES
    unique_social_volume_telegram_5m,12h,YES
    unique_social_volume_reddit_5m,12h,YES
    whale_transaction_volume_100k_usd_to_inf,12h,NO
    whale_transaction_volume_1m_usd_to_inf,12h,NO
    aave_v2_action_liquidations_usd,12h,YES
    aave_v3_action_liquidations_usd,12h,YES
    compound_action_liquidations_usd,12h,YES
    compound_v3_action_liquidations_usd,12h,YES
    makerdao_action_liquidations_usd,12h,YES
    morpho_action_liquidations_usd,12h,YES
    spark_action_liquidations_usd,12h,YES
    fluid_action_liquidations_usd,12h,YES
    amount_in_top_holders,NA,YES
    amount_in_exchange_top_holders,NA,YES
    annual_inflation_rate,48h,NO
    btc_s_and_p_price_divergence,48h,NO
    circulation,48h,NO
    circulation_1d,48h,NO
    circulation_10y,48h,NO
    daily_active_addresses,48h,NO
    dev_activity_1d,48h,YES
    dev_activity_contributors_count_7d,48h,YES
    github_activity_1d,48h,YES
    github_activity_contributors_count_7d,48h,YES
    dormant_circulation_10y,48h,NO
    dormant_circulation_180d,48h,NO
    dormant_circulation_2y,48h,NO
    dormant_circulation_365d,48h,NO
    dormant_circulation_3y,48h,NO
    dormant_circulation_5y,48h,NO
    dormant_circulation_7y,48h,NO
    dormant_circulation_8y,48h,NO
    dormant_circulation_90d,48h,NO
    dormant_circulation_9y,48h,NO
    daily_etf_flow,48h,NO
    total_etf_flow,48h,NO
    getTrendingWords,NA,YES
    ethena_staking_apy,48h,NO
    fully_diluted_valuation_usd,48h,NO
    gini_index,48h,NO
    mvrv_long_short_diff_usd,48h,NO
    mvrv_usd,48h,NO
    mvrv_usd_10y,48h,NO
    mvrv_usd_180d,48h,NO
    mvrv_usd_30d,48h,NO
    mvrv_usd_2y,48h,NO
    mvrv_usd_365d,48h,NO
    mvrv_usd_5y,48h,NO
    mvrv_usd_z_score,48h,NO
    mean_age,48h,NO
    mean_age_5y,48h,NO
    mean_dollar_invested_age,48h,NO
    mean_dollar_invested_age_5y,48h,NO
    nvt,48h,NO
    pendle_implied_apy,48h,NO
    holders_distribution_over_100k,48h,NO
    holders_distribution_over_1M,48h,NO
    active_holders_distribution_total,48h,NO
    active_holders_distribution_over_1,48h,NO
    holders_distribution_combined_balance_over_100k,48h,NO
    holders_distribution_combined_balance_over_1M,48h,NO
    active_holders_distribution_combined_balance_over_1,48h,NO
    holders_labeled_distribution_combined_balance_total,48h,YES
    """
  end
end
