defmodule Sanbase.Metric.Registry.Populate do
  @moduledoc ~s"""
  Migrate the info about Clickhouse metrics from local JSON files to DB
  """
  def run() do
    Sanbase.Repo.transaction(fn ->
      populate()
    end)
  end

  def populate() do
    Sanbase.Clickhouse.MetricAdapter.FileHandler.raw_metrics_json()
    |> Enum.reduce_while([], fn map, acc ->
      {:ok, captures} = Sanbase.TemplateEngine.Captures.extract_captures(map["metric"])
      is_template_metric = captures != []

      changeset =
        %Sanbase.Metric.Registry{}
        |> Sanbase.Metric.Registry.changeset(%{
          metric: map["name"],
          internal_metric: map["metric"],
          human_readable_name: map["human_readable_name"],
          aliases: Map.get(map, "aliases", []),
          table: map["table"] |> List.wrap(),
          aggregation: map["aggregation"],
          min_interval: map["min_interval"],
          is_template_metric: is_template_metric,
          parameters: Map.get(map, "parameters", []),
          is_deprecated: Map.get(map, "is_deprecated", false),
          hard_deprecate_after: map["hard_deprecate_after"],
          has_incomplete_data: Map.get(map, "has_incomplete_data", false),
          data_type: map["data_type"],
          docs_links: Map.get(map, "docs_links", []),
          is_timebound: Map.get(map, "is_timebound", false)
        })

      case Sanbase.Repo.insert(changeset, on_conflict: :nothing) do
        {:ok, result} -> {:cont, [result | acc]}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      list when is_list(list) ->
        {:ok, list}

      {:error, error} ->
        IO.puts("Error: #{Sanbase.Utils.ErrorHandling.changeset_errors_string(error)}")
        {:error, error}
    end
  end
end
