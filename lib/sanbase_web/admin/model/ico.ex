defmodule Sanbase.ExAdmin.Model.Ico do
  use ExAdmin.Register

  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency

  register_resource Sanbase.Model.Ico do

    controller do
      # doc: https://hexdocs.pm/ex_admin/ExAdmin.Register.html#after_filter/2
      after_filter :set_defaults, only: [:new]
    end
  end

  def set_defaults(conn, params, resource, :new) do
    resource = resource
    |> set_cap_currency_default()
    |> set_start_date_default()
    |> set_end_date_default()
    |> set_project_default(params)

    {conn, params, resource}
  end

  defp set_project_default(%Ico{project_id: nil}=ico, params) do
    Map.get(params, :project_id, nil)
    |> case do
      nil -> ico
      project_id -> Map.put(ico, :project_id, project_id)
    end
  end

  defp set_project_default(%Ico{}=ico), do: ico

  defp set_cap_currency_default(%Ico{cap_currency_id: nil}=ico) do
    currency = Currency.get("ETH")

    case currency do
      %Currency{id: id} -> Map.put(ico, :cap_currency_id, id)
      _ -> ico
    end
  end

  defp set_cap_currency_default(%Ico{}=ico), do: ico

  defp set_start_date_default(%Ico{start_date: nil}=ico) do
    Map.put(ico, :start_date, Ecto.Date.utc())
  end

  defp set_start_date_default(%Ico{}=ico), do: ico

  defp set_end_date_default(%Ico{end_date: nil}=ico) do
    Map.put(ico, :end_date, Ecto.Date.utc())
  end

  defp set_end_date_default(%Ico{}=ico), do: ico
end
