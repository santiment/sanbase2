defmodule Sanbase.Metric.Registry.Populate do
  @moduledoc ~s"""
  Migrate the info about Clickhouse metrics from local JSON files to DB
  """
  def run() do
    Sanbase.Repo.transaction(fn ->
      populate()
    end)
    |> case do
      {:ok, {:ok, result}} -> {:ok, result}
      data -> data
    end
  end

  def json_map_to_registry_changeset(%{} = map) do
    {:ok, captures} = Sanbase.TemplateEngine.Captures.extract_captures(map["name"])
    is_template = captures != []

    %Sanbase.Metric.Registry{}
    |> Sanbase.Metric.Registry.changeset(%{
      access: map["access"],
      default_aggregation: map["aggregation"],
      aliases: Map.get(map, "aliases", []) |> Enum.map(&%{name: &1}),
      data_type: map["data_type"],
      deprecation_note: map["deprecation_note"],
      docs: Map.get(map, "docs_links", []) |> Enum.map(&%{link: &1}),
      fixed_parameters: Map.get(map, "fixed_parameters", %{}),
      hard_deprecate_after: map["hard_deprecate_after"],
      has_incomplete_data: Map.get(map, "has_incomplete_data", false),
      human_readable_name: map["human_readable_name"],
      internal_metric: map["metric"],
      is_deprecated: Map.get(map, "is_deprecated", false),
      is_hidden: Map.get(map, "is_hidden", false),
      is_template: is_template,
      is_timebound: Map.get(map, "is_timebound", false),
      metric: map["name"],
      min_interval: map["min_interval"],
      min_plan: Map.get(map, "min_plan", %{}),
      parameters: Map.get(map, "parameters", []),
      required_selectors: Map.get(map, "required_selectors", []) |> Enum.map(&%{type: &1}),
      selectors: Map.get(map, "selectors", []) |> Enum.map(&%{type: &1}),
      tables: map["table"] |> List.wrap() |> Enum.map(&%{name: &1})
    })
  end

  def populate() do
    Sanbase.Clickhouse.MetricAdapter.FileHandler.raw_metrics_json()
    |> Enum.reduce_while([], fn map, acc ->
      changeset = json_map_to_registry_changeset(map)

      case Sanbase.Repo.insert(changeset,
             on_conflict: :replace_all,
             conflict_target: [:metric, :fixed_parameters, :data_type]
           ) do
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
