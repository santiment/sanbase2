defmodule Sanbase.Metric.Utils do
  def available_metrics_for_contract(module, contract_address) do
    Sanbase.Project.List.by_contracts(List.wrap(contract_address))
    |> Enum.map(& &1.slug)
    |> case do
      [] -> []
      [slug | _rest] -> module.available_metrics(%{slug: slug})
    end
  end

  @doc ~s"""
  Sorts a list of version strings in ascending or descending order.

  Version strings are parsed by splitting on "." and converting each segment to an integer.
  -alpha and -beta suffixes are handled by assigning them specific integer values for sorting purposes.

  ## Examples

      iex> Sanbase.Metric.Utils.sort_versions(["1.2.0", "1.10.0", "1.1.0"])
      ["1.1.0", "1.2.0", "1.10.0"]

      iex> Sanbase.Metric.Utils.sort_versions(["1.2.0", "1.10.0", "1.1.0"], :desc)
      ["1.10.0", "1.2.0", "1.1.0"]

      iex> Sanbase.Metric.Utils.sort_versions(["2.0", "1.0", "3.0"])
      ["1.0", "2.0", "3.0"]

      iex> Sanbase.Metric.Utils.sort_versions(["1.0-beta", "1.0", "1.0-alpha"])
      ["1.0", "1.0-alpha", "1.0-beta"]

      iex> Sanbase.Metric.Utils.sort_versions(["1.0.0", "1.0", "1.0.1"])
      ["1.0", "1.0.0", "1.0.1"]

      iex> Sanbase.Metric.Utils.sort_versions([])
      []

      iex> Sanbase.Metric.Utils.sort_versions(["1.0"])
      ["1.0"]

  """
  def sort_versions(list, direction \\ :asc) when direction in [:asc, :desc] do
    list
    |> Enum.sort_by(
      fn ver ->
        String.split(ver, [".", "-"])
        |> Enum.map(fn segment ->
          # Handle things like 1.0-beta, etc.
          case Integer.parse(segment) do
            {int, _} ->
              int

            :error ->
              case segment do
                "alpha" -> 1
                "beta" -> 2
                _ -> 0
              end
          end
        end)
      end,
      direction
    )
  end
end
