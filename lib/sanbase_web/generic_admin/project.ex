defmodule SanbaseWeb.GenericAdmin.Project do
  import Ecto.Query

  def schema_module, do: Sanbase.Project

  def resource() do
    %{
      preloads: [:infrastructure],
      index_fields: [
        :id,
        :ticker,
        :name,
        :slug,
        :website_link,
        :infrastructure_id,
        :token_decimals,
        :is_hidden
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
        :telegram_chat_id,
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
          transform: fn rows -> Enum.map(rows, &{&1.code, &1.id}) end
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
        :telegram_chat_id,
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
      funcs: %{
        infrastructure_id: &__MODULE__.link/1
      }
    }
  end

  def has_many(project) do
    project = project |> Sanbase.Repo.preload([:eth_addresses, :market_segments])

    [
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
      }
    ]
  end

  def link(row) do
    if row.infrastructure do
      SanbaseWeb.GenericAdmin.Subscription.href(
        "infrastructures",
        row.infrastructure.id,
        row.infrastructure.code
      )
    end
  end
end

defmodule SanbaseWeb.GenericAdmin.Infrastructure do
  def schema_module, do: Sanbase.Model.Infrastructure

  def resource() do
    %{
      new_fields: [:code],
      edit_fields: [:code]
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.ProjectMarketSegments do
  import Ecto.Query
  def schema_module, do: Sanbase.Project.ProjectMarketSegment

  def resource() do
    %{
      new_fields: [:project, :market_segment],
      edit_fields: [:project, :market_segment],
      belongs_to_fields: %{
        market_segment: %{
          query: from(ms in Sanbase.Model.MarketSegment, order_by: ms.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end
        },
        project: %{
          query: from(p in Sanbase.Project, order_by: p.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end
        }
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.ProjectEthAddress do
  import Ecto.Query
  def schema_module, do: Sanbase.ProjectEthAddress

  def resource() do
    %{
      new_fields: [:project, :address],
      edit_fields: [:project, :address],
      belongs_to_fields: %{
        project: %{
          query: from(p in Sanbase.Project, order_by: p.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end
        }
      }
    }
  end
end
