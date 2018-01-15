defmodule Sanbase.ExAdmin.Model.Project do
  use ExAdmin.Register

  import Ecto.Query, warn: false

  alias Sanbase.Model.Project
  alias Sanbase.Model.Infrastructure
  alias Sanbase.Model.MarketSegment
  alias Sanbase.Model.ProjectTransparencyStatus

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
          column :token_usd_ico_price
          column :token_eth_ico_price
          column :token_btc_ico_price
          column :tokens_issued_at_ico
          column :tokens_sold_at_ico
          column :funds_raised_btc
          column :funds_raised_usd
          column :funds_raised_eth
          column :minimal_cap_amount
          column :maximal_cap_amount
          column :main_contract_address
          column :comments
          column :cap_currency
        end
      end
    end

    form project do
      inputs do
        input project, :name
        input project, :ticker
        input project, :logo_url
        input project, :website_link
        input project, :btt_link
        input project, :facebook_link
        input project, :github_link
        input project, :reddit_link
        input project, :twitter_link
        input project, :whitepaper_link
        input project, :blog_link
        input project, :slack_link
        input project, :linkedin_link
        input project, :telegram_link
        input project, :token_address
        input project, :team_token_wallet
        input project, :project_transparency
        input project, :project_transparency_status, collection: from(pt in ProjectTransparencyStatus, order_by: pt.name) |> Sanbase.Repo.all()
        input project, :project_transparency_description
        input project, :market_segment, collection: from(m in MarketSegment, order_by: m.name) |> Sanbase.Repo.all()
        input project, :infrastructure, collection: from(i in Infrastructure, order_by: i.code) |> Sanbase.Repo.all()
        input project, :coinmarketcap_id
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
