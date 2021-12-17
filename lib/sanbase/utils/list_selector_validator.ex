defmodule Sanbase.Utils.ListSelector.Validator do
  import Norm

  def valid_args?(args) do
    case args do
      %{selector: %{}} -> true
      _ -> {:error, "Invalid selector - it must have a 'selector' top key."}
    end
  end

  def valid_filters_combinator?(args) do
    filters_combinator =
      (get_in(args, [:selector, :filters_combinator]) || "and")
      |> to_string()
      |> String.downcase()

    case filters_combinator in ["and", "or"] do
      true ->
        true

      false ->
        {:error,
         """
         Unsupported filter_combinator #{inspect(filters_combinator)}.
         Supported filter combinators are 'and' and 'or'.
         """}
    end
  end

  def valid_base_projects?(args) do
    base_projects_list = get_in(args, [:selector, :base_projects]) || [:all]

    base_projects_list
    |> Enum.map(fn base_projects ->
      case base_projects do
        :all ->
          true

        %{watchlist_id: id} when is_integer(id) ->
          true

        %{watchlist_slug: slug} when is_binary(slug) ->
          true

        %{slugs: [_ | _]} ->
          true

        _ ->
          {:error,
           """
           Unsupported base_projects #{inspect(base_projects)}.
           Supported base projects are '{"watchlist_id": <integer>}',
           '{"watchlsit_slug": "<string>"}' or '{"slugs": [<list of strings>]}'.
           """}
      end
    end)
    |> Enum.find(true, &match?({:error, _}, &1))
  end

  def valid_order_by?(order_by) do
    order_by_schema =
      schema(%{
        metric: spec(is_binary()),
        from: spec(&match?(%DateTime{}, &1)),
        to: spec(&match?(%DateTime{}, &1)),
        direction: spec(is_atom())
      })

    with {:ok, _} <- conform(order_by, order_by_schema) do
      true
    end
  end

  def valid_pagination?(pagination) do
    pagination_schema =
      schema(%{
        page: spec(&(is_integer(&1) and &1 > 0)),
        page_size: spec(&(is_integer(&1) and &1 > 0))
      })

    with {:ok, _} <- conform(pagination, pagination_schema) do
      true
    end
  end

  def valid_filters?(filters, type) do
    case Enum.all?(filters, &is_map/1) do
      true ->
        filters
        |> Enum.map(&valid_filter?(type, &1))
        |> Enum.find(&(&1 != true))
        |> case do
          nil -> true
          error -> error
        end

      false ->
        {:error, "Individual filters inside the filters list must be a map."}
    end
  end

  def valid_filter?(:project, %{name: "traded_on_exchanges", args: %{exchanges: list} = args}) do
    combinator = Map.get(args, :exchanges_combinator, "and")

    case is_list(list) and list != [] do
      true ->
        case combinator in ["and", "or"] do
          true ->
            true

          false ->
            {:error,
             """
             Unsupported exchanges_combinator: #{inspect(combinator)}.
             Supported values for that combinator are 'and' and 'or'.
             """}
        end

      false ->
        {:error, "The traded_on_exchanges filter must provide a non-empty list of 'exchanges'."}
    end
  end

  def valid_filter?(:project, %{name: "market_segments", args: %{market_segments: list} = args}) do
    combinator = Map.get(args, :market_segments_combinator, "and")

    case is_list(list) and list != [] do
      true ->
        case combinator in ["and", "or"] do
          true ->
            true

          false ->
            {:error,
             """
             Unsupported market_segments_combinator: #{inspect(combinator)}.
             Supported values for that combinators are 'and' and 'or'.
             """}
        end

      false ->
        {:error, "The market segments filter must provide a non-empty list of 'market_segments'."}
    end
  end

  # Could be reworked to `name: "metric"` after the FE starts using this
  def valid_filter?(:project, %{metric: metric} = filter) do
    metric_filter(metric, filter)
  end

  def valid_filter?(:project, %{name: "metric", args: %{metric: metric} = filter}) do
    metric_filter(metric, filter)
  end

  def valid_filter?(
        :blockchain_address,
        %{name: "top_addresses", args: %{slug: _, page: _, page_size: _} = filter}
      ) do
    filter_schema =
      schema(%{
        slug: spec(is_binary()),
        page: spec(is_integer() and (&(&1 > 0))),
        page_size: spec(is_integer() and (&(&1 > 0))),
        labels: spec(is_list() and (&(length(&1) > 0)))
      })

    with {:ok, _} <- conform(filter, filter_schema) do
      true
    end
  end

  def valid_filter?(
        :blockchain_address,
        %{name: "addresses_by_labels", args: %{label_fqns: _} = filter}
      ) do
    filter_schema =
      schema(%{
        blockchain: spec(is_binary()),
        labels_combinator: spec(is_binary()),
        label_fqns: spec(is_list() and (&(length(&1) > 0)))
      })

    with {:ok, _} <- conform(filter, filter_schema) do
      true
    end
  end

  def valid_filter?(
        :blockchain_address,
        %{name: "addresses_by_label_keys", args: %{label_fqns: _} = filter}
      ) do
    filter_schema =
      schema(%{
        blockchain: spec(is_binary()),
        label_keys: spec(is_list() and (&(length(&1) > 0)))
      })

    with {:ok, _} <- conform(filter, filter_schema) do
      true
    end
  end

  def valid_filter?(type, filter),
    do:
      {:error,
       "The #{inspect(type)} filter #{inspect(filter)} is not supported or has mistyped fields."}

  def metric_filter(metric, filter) do
    filter_schema =
      schema(%{
        name: spec(is_binary()),
        metric: spec(is_binary()),
        from: spec(&match?(%DateTime{}, &1)),
        to: spec(&match?(%DateTime{}, &1)),
        dynamic_from: spec(is_binary()),
        dynamic_to: spec(is_binary()),
        operator: spec(is_atom()),
        threshold: spec(is_number() or is_list()),
        aggregation: spec(is_atom())
      })

    with {:ok, _} <- conform(filter, filter_schema),
         true <- Sanbase.Metric.has_metric?(metric) do
      missing_fields =
        [:metric, :from, :to, :operator, :threshold, :aggregation] -- Map.keys(filter)

      case missing_fields do
        [] -> true
        _ -> {:error, "A metric filter has missing fields: #{inspect(missing_fields)}."}
      end
    end
  end
end
