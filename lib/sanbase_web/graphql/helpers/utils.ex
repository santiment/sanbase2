defmodule SanbaseWeb.Graphql.Helpers.Utils do
  import Sanbase.DateTimeUtils, only: [round_datetime: 2, str_to_sec: 1]

  def resolution_to_user_id_or_nil(resolution) do
    case resolution do
      %{context: %{auth: %{current_user: %{id: user_id}}}} ->
        user_id

      _ ->
        nil
    end
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
  """
  def fit_from_datetime([%{datetime: _} | _] = data, %{from: from, interval: interval}) do
    interval_sec = str_to_sec(interval)
    from = round_datetime(from, second: interval_sec)

    result =
      Enum.drop_while(data, fn %{datetime: datetime} ->
        datetime = round_datetime(datetime, second: interval_sec)
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
      | trigger:
          trigger
          |> Map.put(:tags, tags)
          |> Map.put(:id, ut.id)
          |> Map.put(:is_hidden, ut.is_hidden)
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

  def requested_fields(_), do: MapSet.new([])

  # Private functions
  @fields [:owner, :label, :label_fqn, :label_fqns, :blockchain, :owners, :labels]
  defp maybe_add_field(opts, :additional_filters, selector) do
    case Map.split(selector, @fields) do
      {map, _rest} when map_size(map) > 0 ->
        # Rename the plurals to singulars. This is done to simplify the
        # SQL generation
        map =
          map
          |> maybe_rename_field(:owners, :owner)
          |> maybe_rename_field(:labels, :label)
          |> maybe_rename_field(:label_fqns, :label_fqn)

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

  defp maybe_rename_field(map, old_key, new_key) do
    case Map.has_key?(map, old_key) do
      true ->
        value = Map.get(map, old_key)
        map |> Map.delete(old_key) |> Map.put(new_key, value)

      false ->
        map
    end
  end
end
