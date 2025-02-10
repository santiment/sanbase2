defmodule Sanbase.Metric.Utils do
  @moduledoc false
  def available_metrics_for_contract(module, contract_address) do
    contract_address
    |> List.wrap()
    |> Sanbase.Project.List.by_contracts()
    |> Enum.map(& &1.slug)
    |> case do
      [] -> []
      [slug | _rest] -> module.available_metrics(%{slug: slug})
    end
  end
end
