defmodule Sanbase.Metric do
  @moduledoc """
  Dispatch module
  TODO DOCS
  """

  alias Sanbase.Clickhouse
  alias Sanbase.TechIndicators

  @clickhouse_metrics_mapset MapSet.new(Clickhouse.Metric.available_metrics!())

  @doc ~s"""
  TODO
  """
  def get(metric, identifier, from, to, interval, opts) do
    if metric in @clickhouse_metrics_mapset do
      {:clickhouse_metric, metric}
    else
      metric
    end
    |> get_metric(identifier, from, to, interval, opts)
  end

  @doc ~s"""
  TODO
  """
  def metadata(metric) do
    if metric in @clickhouse_metrics_mapset do
      {:clickhouse_metric, metric}
    else
      metric
    end
    |> get_metadata()
  end

  @doc ~s"""
  TODO
  """
  def first_datetime(metric, slug) do
    if metric in @clickhouse_metrics_mapset do
      {:clickhouse_metric, metric}
    else
      metric
    end
    |> get_first_datetime(slug)
  end

  @doc ~s"""
  TODO
  """
  def available_metrics(), do: Clickhouse.Metric.available_metrics()

  def available_metrics!() do
    {:ok, result} = available_metrics()
    result
  end

  @doc ~s"""
  TODO
  """
  def available_slugs_all_metrics(), do: Clickhouse.Metric.available_slugs()

  @doc ~s"""
  TODO
  """
  def available_slugs(_metric) do
    Clickhouse.Metric.available_slugs()
  end

  def free_metrics(), do: Sanbase.Clickhouse.Metric.free_metrics()
  def restricted_metrics(), do: Sanbase.Clickhouse.Metric.restricted_metrics()

  # Private functions
  defp get_metric({:clickhouse_metric, metric}, identifier, from, to, interval, opts) do
    Clickhouse.Metric.get(
      metric,
      identifier,
      from,
      to,
      interval,
      Keyword.get(opts, :aggregation)
    )
  end

  defp get_metric("dev_activity", identifier, from, to, interval, opts) do
    Clickhouse.Github.dev_activity(
      identifier,
      from,
      to,
      interval,
      Keyword.get(opts, :transformation),
      Keyword.get(opts, :ma_base)
    )
    |> transform_to_value_pairs(:activity)
  end

  defp get_metric("github_activity", identifier, from, to, interval, opts) do
    Clickhouse.Github.github_activity(
      identifier,
      from,
      to,
      interval,
      Keyword.get(opts, :transformation),
      Keyword.get(opts, :ma_base)
    )
    |> transform_to_value_pairs(:activity)
  end

  defp get_metric("discord_social_volume", identifier, from, to, interval, _opts) do
    TechIndicators.social_volume(
      identifier,
      from,
      to,
      interval,
      :discord_discussion_overview
    )
    |> transform_to_value_pairs(:mentions_count)
  end

  defp get_metric("telegram_social_volume", identifier, from, to, interval, _opts) do
    TechIndicators.social_volume(
      identifier,
      from,
      to,
      interval,
      :telegram_discussion_overview
    )
    |> transform_to_value_pairs(:mentions_count)
  end

  defp get_metric(
         "professional_traders_chat_social_volume",
         identifier,
         from,
         to,
         interval,
         _opts
       ) do
    TechIndicators.social_volume(
      identifier,
      from,
      to,
      interval,
      :professional_traders_chat_overview
    )
    |> transform_to_value_pairs(:mentions_count)
  end

  defp get_metric(metric, _, _, _, _, _), do: {:error, "The '#{metric}' metric is not supported."}

  defp transform_to_value_pairs({:ok, result}, key_name) do
    result =
      result
      |> Enum.map(fn %{^key_name => value, datetime: datetime} ->
        %{value: value, datetime: datetime}
      end)

    {:ok, result}
  end

  defp transform_to_value_pairs({:error, error}, _), do: {:error, error}

  defp get_metadata({:clickhouse_metric, metric}), do: Clickhouse.Metric.metadata(metric)
  defp get_metadata("dev_activity" = metric), do: Clickhouse.Github.metadata(metric)
  defp get_metadata("github_activity" = metric), do: Clickhouse.Github.metadata(metric)
  defp get_metadata("discord_social_volume" = metric), do: TechIndicators.Metadata.get(metric)
  defp get_metadata("telegram_social_volume" = metric), do: TechIndicators.Metadata.get(metric)

  defp get_metadata("professional_traders_chat_social_volume" = metric),
    do: TechIndicators.Metadata.get(metric)

  defp get_metadata(metric), do: {:error, "The '#{metric}' metric is not supported."}

  defp get_first_datetime({:clickhouse_metric, metric}, slug),
    do: Clickhouse.Metric.first_datetime(metric, slug)

  defp get_first_datetime("dev_activity", slug), do: Clickhouse.Github.first_datetime(slug)
  defp get_first_datetime("github_activity", slug), do: Clickhouse.Github.first_datetime(slug)

  defp get_first_datetime("discord_social_volume", slug),
    do: TechIndicators.Metadata.first_datetime(slug)

  defp get_first_datetime("telegram_social_volume", slug),
    do: TechIndicators.Metadata.first_datetime(slug)

  defp get_first_datetime("professional_traders_chat_social_volume", slug),
    do: TechIndicators.Metadata.first_datetime(slug)

  defp get_first_datetime(metric, _), do: {:error, "The '#{metric}' metric is not supported."}
end
