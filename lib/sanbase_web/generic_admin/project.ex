defmodule SanbaseWeb.GenericAdmin.Project do
  @behaviour SanbaseWeb.GenericAdmin
  import Ecto.Query

  def schema_module, do: Sanbase.Project
  def resource_name, do: "projects"
  def singular_resource_name, do: "project"

  def resource() do
    %{
      actions: [:new, :edit],
      preloads: [:infrastructure],
      index_fields: [
        :id,
        :ticker,
        :name,
        :slug,
        :website_link,
        :infrastructure_id,
        :token_decimals,
        :is_hidden,
        :telegram_chat_name
      ],
      new_fields: [
        :name,
        :ticker,
        :slug,
        :description,
        :long_description,
        :token_supply,
        :infrastructure,
        :token_decimals,
        :is_hidden,
        :hidden_reason,
        :telegram_chat_id,
        :telegram_chat_name,
        :logo_url,
        :dark_logo_url,
        :email,
        :blog_link,
        :btt_link,
        :facebook_link,
        :linkedin_link,
        :reddit_link,
        :slack_link,
        :discord_link,
        :telegram_link,
        :twitter_link,
        :website_link,
        :whitepaper_link
      ],
      belongs_to_fields: %{
        infrastructure: %{
          query: from(i in Sanbase.Model.Infrastructure, order_by: i.code),
          transform: fn rows -> Enum.map(rows, &{&1.code, &1.id}) end,
          resource: "infrastructures",
          search_fields: [:code]
        }
      },
      edit_fields: [
        :name,
        :ticker,
        :slug,
        :description,
        :long_description,
        :token_supply,
        :infrastructure,
        :token_decimals,
        :is_hidden,
        :hidden_reason,
        :telegram_chat_id,
        :telegram_chat_name,
        :logo_url,
        :dark_logo_url,
        :email,
        :blog_link,
        :btt_link,
        :facebook_link,
        :linkedin_link,
        :reddit_link,
        :slack_link,
        :discord_link,
        :telegram_link,
        :twitter_link,
        :website_link,
        :whitepaper_link
      ],
      fields_override: %{
        long_description: %{
          type: :text
        },
        infrastructure_id: %{
          value_modifier: &__MODULE__.link/1
        }
      }
    }
  end

  def has_many(project) do
    project =
      project
      |> Sanbase.Repo.preload([
        :contract_addresses,
        :github_organizations,
        :eth_addresses,
        :market_segments,
        :source_slug_mappings,
        :icos,
        :latest_coinmarketcap_data,
        :social_volume_query,
        :ecosystems
      ])

    [
      %{
        resource: "contract_addresses",
        actions: [:edit, :delete],
        resource_name: "Contract Addresses",
        rows: project.contract_addresses,
        fields: [:id, :address],
        funcs: %{},
        create_link_kv: [linked_resource: :project, linked_resource_id: project.id]
      },
      %{
        resource: "github_organizations",
        resource_name: "Github Organizations",
        rows: project.github_organizations,
        fields: [:id, :organization],
        funcs: %{},
        create_link_kv: [linked_resource: :project, linked_resource_id: project.id]
      },
      %{
        resource: "project_eth_addresses",
        resource_name: "ETH Addresses",
        rows: project.eth_addresses,
        fields: [:id, :address],
        funcs: %{},
        create_link_kv: [linked_resource: :project, linked_resource_id: project.id]
      },
      %{
        resource: "project_market_segments",
        resource_name: "Market Segments",
        rows: project.market_segments,
        fields: [:id, :name, :type],
        funcs: %{},
        create_link_kv: [linked_resource: :project, linked_resource_id: project.id]
      },
      %{
        resource: "project_ecosystem_mappings",
        resource_name: "Project Ecosystems",
        rows: project.ecosystems,
        fields: [:id, :ecosystem],
        funcs: %{},
        create_link_kv: [linked_resource: :project, linked_resource_id: project.id]
      },
      %{
        resource: "source_slug_mappings",
        resource_name: "Slug Source Mappings",
        rows: project.source_slug_mappings,
        fields: [:id, :source, :slug],
        funcs: %{},
        create_link_kv: [linked_resource: :project, linked_resource_id: project.id]
      },
      %{
        resource: "icos",
        resource_name: "ICO events",
        rows: project.icos,
        fields: [
          :id,
          :start_date,
          :end_date,
          :token_usd_ico_price,
          :token_eth_ico_price,
          :token_btc_ico_price,
          :tokens_issued_at_ico,
          :tokens_sold_at_ico,
          :minimal_cap_amount,
          :maximal_cap_amount
        ],
        funcs: %{},
        create_link_kv: [linked_resource: :project, linked_resource_id: project.id]
      },
      %{
        resource: "latest_coinmarketcap_data",
        resource_name: "Latest Coinmarketcap Data",
        rows:
          if(project.latest_coinmarketcap_data, do: [project.latest_coinmarketcap_data], else: []),
        fields: [
          :id,
          :coinmarketcap_id,
          :coinmarketcap_integer_id,
          :rank,
          :price_usd,
          :price_btc,
          :volume_usd,
          :market_cap_usd,
          :available_supply,
          :total_supply,
          :logo_updated_at,
          :update_time
        ],
        funcs: %{},
        create_link_kv: []
      },
      %{
        resource: "social_volume_queries",
        resource_name: "Social Volume Query",
        rows: if(project.social_volume_query, do: [project.social_volume_query], else: []),
        fields: [:id, :query, :autogenerated_query],
        funcs: %{},
        create_link_kv:
          if(project.social_volume_query,
            do: [],
            else: [linked_resource: :project, linked_resource_id: project.id]
          )
      }
    ]
  end

  def link(row) do
    if row.infrastructure do
      SanbaseWeb.GenericAdmin.resource_link(
        "infrastructures",
        row.infrastructure.id,
        row.infrastructure.code
      )
    end
  end

  def project_link(row) do
    if row.project_id do
      SanbaseWeb.GenericAdmin.resource_link(
        "projects",
        row.project_id,
        row.project.name
      )
    end
  end
end
