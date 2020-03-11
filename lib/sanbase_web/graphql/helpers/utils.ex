defmodule SanbaseWeb.Graphql.Helpers.Utils do
  alias Sanbase.DateTimeUtils

  def calibrate_interval(
        module,
        measurement,
        from,
        to,
        interval,
        min_interval_seconds \\ 300,
        data_points_count \\ 500
      )

  def calibrate_interval(
        module,
        measurement,
        from,
        to,
        "",
        min_interval_seconds,
        data_points_count
      ) do
    with {:ok, first_datetime} <- module.first_datetime(measurement) do
      first_datetime = first_datetime || from

      from =
        max(
          DateTime.to_unix(from, :second),
          DateTime.to_unix(first_datetime, :second)
        )

      interval =
        max(
          div(DateTime.to_unix(to, :second) - from, data_points_count),
          min_interval_seconds
        )

      {:ok, DateTime.from_unix!(from), to, "#{interval}s"}
    end
  end

  def calibrate_interval(
        _module,
        _measurement,
        from,
        to,
        interval,
        _min_interval,
        _data_points_count
      ) do
    {:ok, from, to, interval}
  end

  def calibrate_interval(
        module,
        metric,
        slug,
        from,
        to,
        "",
        min_interval_seconds,
        data_points_count
      ) do
    {:ok, first_datetime} = module.first_datetime(metric, slug)

    first_datetime = first_datetime || from

    from =
      max(
        DateTime.to_unix(from, :second),
        DateTime.to_unix(first_datetime, :second)
      )

    interval =
      max(
        div(DateTime.to_unix(to, :second) - from, data_points_count),
        min_interval_seconds
      )

    {:ok, DateTime.from_unix!(from), to, "#{interval}s"}
  end

  def calibrate_interval(
        _module,
        _metric,
        _slug,
        from,
        to,
        interval,
        _min_interval,
        _data_points_count
      ) do
    {:ok, from, to, interval}
  end

  def calibrate_interval_with_ma_interval(
        module,
        measurement,
        from,
        to,
        interval,
        min_interval,
        ma_base,
        data_points_count \\ 500
      ) do
    {:ok, from, to, interval} =
      calibrate_interval(module, measurement, from, to, interval, min_interval, data_points_count)

    ma_interval =
      max(
        div(
          DateTimeUtils.str_to_sec(ma_base),
          DateTimeUtils.str_to_sec(interval)
        ),
        2
      )

    {:ok, from, to, interval, ma_interval}
  end

  def calibrate_incomplete_data_params(true, _module, _identifier, from, to) do
    {:ok, from, to}
  end

  def calibrate_incomplete_data_params(false, module, identifier, from, to) do
    case module.has_incomplete_data?(identifier) do
      true -> rewrite_params_incomplete_data(from, to)
      false -> {:ok, from, to}
    end
  end

  defp rewrite_params_incomplete_data(from, to) do
    start_of_day = Timex.beginning_of_day(Timex.now())

    case DateTime.compare(from, start_of_day) != :lt do
      true ->
        {:error,
         """
         The time range provided [#{from} - #{to}] is contained in today. The metric
         requested could have incomplete data as it's calculated since the beginning
         of the day and not for the last 24 hours. If you still want to see this
         data you can pass the flag `includeIncompleteData: true` in the
         `timeseriesData` arguments
         """}

      false ->
        to = if DateTime.compare(to, start_of_day) == :gt, do: start_of_day, else: to
        {:ok, from, to}
    end
  end

  def error_details(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&format_error/1)
  end

  @doc ~s"""
  Works when the result is a list of elements that contain a datetime and the query arguments
  have a `from` argument. In that case the first element's `datetime` is update to be
  the max of `datetime` and `from` from the query.
  This is used when a query to influxdb is made. Influxdb can return a timestamp
  that's outside `from` - `to` interval due to its inner working with buckets
  """
  def fit_from_datetime([%{datetime: _} | _] = data, %{from: from}) do
    result =
      data
      |> Enum.drop_while(fn %{datetime: datetime} ->
        DateTime.compare(datetime, from) == :lt
      end)

    {:ok, result}
  end

  def fit_from_datetime(result, _args), do: {:ok, result}

  @doc ~s"""
  Extract the arguments passed to the root query from subfield resolution
  """
  def extract_root_query_args(resolution, root_query_name) do
    root_query_camelized = Absinthe.Utils.camelize(root_query_name, lower: true)

    resolution.path
    |> Enum.find(fn x -> is_map(x) && x.name == root_query_camelized end)
    |> Map.get(:argument_data)
  end

  @doc ~s"""
  Transform the UserTrigger structure to be more easily consumed by the API.
  This is done by propagating the tags and the UserTrigger id into the Trigger
  structure
  """
  def transform_user_trigger(%Sanbase.Signal.UserTrigger{trigger: trigger, tags: tags} = ut) do
    ut = Map.from_struct(ut)
    trigger = Map.from_struct(trigger)

    %{
      ut
      | trigger: trigger |> Map.put(:tags, tags) |> Map.put(:id, ut.id)
    }
  end

  def replace_user_trigger_with_trigger(data) when is_map(data) do
    case data do
      %{user_trigger: ut} = elem when not is_nil(ut) ->
        elem
        |> Map.drop([:__struct__, :user_trigger])
        |> Map.put(:trigger, Map.get(transform_user_trigger(ut), :trigger))

      elem ->
        elem
    end
  end

  def replace_user_trigger_with_trigger(data) when is_list(data) do
    data |> Enum.map(&replace_user_trigger_with_trigger/1)
  end

  @spec requested_fields(%Absinthe.Resolution{}) :: MapSet.t()
  def requested_fields(%Absinthe.Resolution{} = resolution) do
    resolution.definition.selections
    |> Enum.map(fn %{name: name} -> Inflex.camelize(name, :lower) end)
    |> MapSet.new()
  end

  # Private functions

  @spec format_error(Ecto.Changeset.error()) :: String.t()
  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(inspect(value)))
    end)
  end
end
