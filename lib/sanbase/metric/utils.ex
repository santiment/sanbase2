defmodule Sanbase.Metric.Utils do
  def available_metrics_for_contract(module, contract_address) do
    Sanbase.Project.List.by_contracts(List.wrap(contract_address))
    |> Enum.map(& &1.slug)
    |> case do
      [] -> []
      [slug | _rest] -> module.available_metrics(%{slug: slug})
    end
  end
end
