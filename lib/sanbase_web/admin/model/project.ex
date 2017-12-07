defmodule Sanbase.ExAdmin.Model.Project do
  use ExAdmin.Register

  alias Sanbase.Model.Project
  alias Sanbase.Model.Infrastructure

  register_resource Sanbase.Model.Project do

    show project do
      attributes_table

      panel "Icos" do
        markup_contents do
          a ".btn .btn-primary", href: "/admin/icos/new?project_id="<>to_string(project.id) do
            "New Ico"
          end
        end

        table_for Sanbase.Repo.preload(project.icos, :cap_currency) do
          column :id, link: true
          column :start_date
          column :end_date
          column :tokens_issued_at_ico
          column :tokens_sold_at_ico
          column :funds_raised_btc
          column :funds_raised_usd
          column :funds_raised_eth
          column :usd_btc_icoend
          column :usd_eth_icoend
          column :minimal_cap_amount
          column :maximal_cap_amount
          column :main_contract_address
          column :comments
          column :cap_currency
        end
      end
    end

    controller do
      # doc: https://hexdocs.pm/ex_admin/ExAdmin.Register.html#after_filter/2
      after_filter :set_defaults, only: [:new]
    end
  end

  def set_defaults(conn, params, resource, :new) do
    resource = resource
    |> set_infrastructure_default()

    {conn, params, resource}
  end

  defp set_infrastructure_default(%Project{infrastructure_id: nil}=project) do
    infrastructure = Infrastructure.get("ETH")

    case infrastructure do
      %Infrastructure{id: id} -> Map.put(project, :infrastructure_id, id)
      _ -> project
    end
  end

  defp set_infrastructure_default(%Project{}=project), do: project
end
