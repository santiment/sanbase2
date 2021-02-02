defmodule SanbaseWeb.Graphql.Helpers.Utils do
  def error_details(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&format_error/1)
  end

  def selector_args_to_opts(args) when is_map(args) do
    opts = [aggregation: Map.get(args, :aggregation, nil)]
    selector = args[:selector]

    opts =
      if is_map(selector) do
        opts
        |> maybe_add_field(:additional_filters, selector)
        |> maybe_add_field(:source, selector)
      else
        opts
      end

    {:ok, opts}
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
  def transform_user_trigger(%Sanbase.Alert.UserTrigger{trigger: trigger, tags: tags} = ut) do
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

  defp maybe_add_field(opts, :additional_filters, selector) do
    case Map.split(selector, [:owner, :label]) do
      {map, _rest} when map_size(map) > 0 ->
        [additional_filters: Keyword.new(map)] ++ opts

      _ ->
        opts
    end
  end

  defp maybe_add_field(opts, field, selector) when is_atom(field) do
    case Map.has_key?(selector, field) do
      true -> [{field, Map.fetch!(selector, field)}] ++ opts
      false -> opts
    end
  end
end
