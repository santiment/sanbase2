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

  def json_map_to_registry_params(%{} = map) do
    {:ok, captures} = Sanbase.TemplateEngine.Captures.extract_captures(map["name"])
    is_template = captures != []

    %{
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
      sanbase_min_plan: get_in(map, ["min_plan", "SANBASE"]) || "free",
      sanapi_min_plan: get_in(map, ["min_plan", "SANAPI"]) || "free",
      parameters: Map.get(map, "parameters", []),
      required_selectors: Map.get(map, "required_selectors", []) |> Enum.map(&%{type: &1}),
      selectors: Map.get(map, "selectors", []) |> Enum.map(&%{type: &1}),
      tables: map["table"] |> List.wrap() |> Enum.map(&%{name: &1})
    }
  end

  def json_map_to_registry_changeset(%{} = map) do
    params = json_map_to_registry_params(map)

    %Sanbase.Metric.Registry{}
    |> Sanbase.Metric.Registry.changeset(params)
  end

  def populate() do
    case process_metrics() do
      list when is_list(list) ->
        summarize_results(list)

      {:error, %Ecto.Changeset{} = error} ->
        log_and_return_changeset_error(error)

      {:error, error} when is_binary(error) ->
        log_and_return_error(error)
    end
  end

  defp process_metrics do
    Sanbase.Clickhouse.MetricAdapter.FileHandler.raw_metrics_json()
    |> Enum.reduce_while([], &process_single_metric/2)
  end

  defp process_single_metric(map, acc) do
    existing_record =
      Sanbase.Metric.Registry.by_name(
        map["name"],
        map["data_type"],
        map["fixed_parameters"] || %{}
      )

    case handle_metric_record(existing_record, map) do
      {type, {:ok, result}} ->
        {:cont, [{type, result} | acc]}

      {:insert, {:error, error}} ->
        log_insert_error(map, error)
        {:halt, {:error, error}}

      {:update, {:error, error}} ->
        log_update_error(map, error)
        {:halt, {:error, error}}
    end
  end

  defp handle_metric_record({:ok, record}, map) do
    params = json_map_to_registry_params(map)
    changeset = Sanbase.Metric.Registry.changeset(record, params)
    new_record = changeset |> Ecto.Changeset.apply_changes()

    case record == new_record do
      true ->
        {:unchanged, {:ok, record}}

      false ->
        {:update, Sanbase.Repo.update(changeset)}
    end
  end

  defp handle_metric_record({:error, _}, map) do
    changeset = json_map_to_registry_changeset(map)
    {:insert, Sanbase.Repo.insert(changeset)}
  end

  defp summarize_results(list) do
    {list, counts} =
      Enum.reduce(list, {[], %{}}, fn {type, record}, {list_acc, count_acc} ->
        {
          [{type, record} | list_acc],
          Map.update(count_acc, type, 1, &(&1 + 1))
        }
      end)

    {:ok, list, counts}
  end

  defp log_and_return_changeset_error(error) do
    IO.puts("Error: #{Sanbase.Utils.ErrorHandling.changeset_errors_string(error)}")
    {:error, error}
  end

  defp log_and_return_error(error) do
    IO.puts(error)
    {:error, error}
  end

  defp log_insert_error(map, error) do
    IO.puts("""
    Error inserting new metric: #{inspect(map)}.
    Reason: #{inspect(error)}
    """)
  end

  defp log_update_error(map, error) do
    IO.puts("""
    Error updating existing metric: #{inspect(map)}
    Reason: #{inspect(error)}
    """)
  end
end
