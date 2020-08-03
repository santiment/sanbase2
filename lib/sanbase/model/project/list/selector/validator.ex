defmodule Sanbase.Model.Project.ListSelector.Validator do
  import Norm

  alias Sanbase.Model.Project.ListSelector.Transform

  def valid_selector?(args) do
    args = Sanbase.MapUtils.atomize_keys(args)
    filters = Transform.args_to_filters(args)

    order_by = Transform.args_to_order_by(args) || %{}
    pagination = Transform.args_to_pagination(args) || %{}

    with true <- valid_args?(args),
         true <- valid_filters_combinator?(args),
         true <- valid_filters?(filters),
         true <- valid_order_by?(order_by),
         true <- valid_pagination?(pagination) do
      true
    end
  end

  defp valid_args?(args) do
    case args do
      %{selector: %{}} -> true
      _ -> {:error, "Invalid selector - it must have a 'selector' top key."}
    end
  end

  defp valid_filters_combinator?(args) do
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
         Unsupported filter combinator #{inspect(filters_combinator)}.
         Supported filter combinators are 'and' and 'or'
         """}
    end
  end

  defp valid_order_by?(order_by) do
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

  defp valid_pagination?(pagination) do
    pagination_schema =
      schema(%{
        page: spec(&(is_integer(&1) and &1 > 0)),
        page_size: spec(&(is_integer(&1) and &1 > 0))
      })

    with {:ok, _} <- conform(pagination, pagination_schema) do
      true
    end
  end

  defp valid_filters?(filters) do
    case Enum.all?(filters, &is_map/1) do
      true ->
        filters
        |> Enum.map(&valid_filter?/1)
        |> Enum.find(&(&1 != true))
        |> case do
          nil -> true
          error -> error
        end

      false ->
        {:error, "Individual filters inside the filters list must be a map."}
    end
  end

  defp valid_filter?(%{name: "market_segments", args: %{market_segments: list}}) do
    case is_list(list) and list != [] do
      true ->
        true

      false ->
        {:error, "Market segments filter must provide a non-empty list of market segments."}
    end
  end

  # Could be reworked to `name: "metric"` after the FE starts using this
  defp valid_filter?(%{metric: metric} = filter) do
    filter_schema =
      schema(%{
        name: spec(is_binary()),
        metric: spec(is_binary()),
        from: spec(&match?(%DateTime{}, &1)),
        to: spec(&match?(%DateTime{}, &1)),
        operator: spec(is_atom()),
        threshold: spec(is_number()),
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

  defp valid_filter?(_), do: {:error, "Filter is wrongly configured."}
end
