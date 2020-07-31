defmodule Sanbase.Model.Project.ListSelector.Validator do
  import Norm

  alias Sanbase.Model.Project.ListSelector.Transform

  def valid_selector?(args) do
    args = Sanbase.MapUtils.atomize_keys(args)

    filters = Transform.args_to_filters(args)
    order_by = Transform.args_to_order_by(args) || %{}
    pagination = Transform.args_to_pagination(args) || %{}

    with true <- check_filters(filters),
         true <- valid_filters_combinator?(args),
         true <- check_order_by(order_by),
         true <- check_pagination(pagination) do
      true
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

  defp check_filters(filters) do
    with true <- filters_structure_valid?(filters),
         true <- filters_metrics_valid?(filters) do
      true
    else
      error -> error
    end
  end

  defp check_order_by(order_by) do
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

  defp check_pagination(pagination) do
    pagination_schema =
      schema(%{
        page: spec(&(is_integer(&1) and &1 > 0)),
        page_size: spec(&(is_integer(&1) and &1 > 0))
      })

    with {:ok, _} <- conform(pagination, pagination_schema) do
      true
    end
  end

  defp filters_metrics_valid?(filters) do
    Enum.map(filters, fn %{metric: metric} ->
      Sanbase.Metric.has_metric?(metric)
    end)
    |> Enum.find(&match?({:error, _}, &1))
    |> case do
      nil -> true
      {:error, error} -> {:error, error}
    end
  end

  @allowed_filter_keys [:metric, :from, :to, :operator, :threshold, :aggregation]
  defp filters_structure_valid?(filters) do
    filter_schema =
      schema(%{
        metric: spec(is_binary()),
        from: spec(&match?(%DateTime{}, &1)),
        to: spec(&match?(%DateTime{}, &1)),
        operator: spec(is_atom()),
        threshold: spec(is_number()),
        aggregation: spec(is_atom())
      })

    filter_does_not_conform = fn filter ->
      match?({:error, _}, conform(filter, filter_schema))
    end

    Enum.find(filters, filter_does_not_conform)
    |> case do
      nil ->
        Enum.map(filters, &(@allowed_filter_keys -- Map.keys(&1)))
        |> Enum.find(&(&1 != []))
        |> case do
          nil -> true
          fields -> {:error, "A filter has missing fields: #{inspect(fields)}."}
        end

      error ->
        error
    end
  end
end
