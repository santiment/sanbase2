defmodule SanbaseWeb.GenericAdmin.Project do
  import Ecto.Query

  def schema_module, do: Sanbase.Project

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
      field_types: %{
        long_description: :text
      },
      funcs: %{
        infrastructure_id: &__MODULE__.link/1
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
        :social_volume_query
      ])

    [
      %{
        resource: "contract_addresses",
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
        resource: "social_volume_query",
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
      SanbaseWeb.GenericAdmin.Subscription.href(
        "infrastructures",
        row.infrastructure.id,
        row.infrastructure.code
      )
    end
  end

  def project_link(row) do
    if row.project_id do
      SanbaseWeb.GenericAdmin.Subscription.href(
        "projects",
        row.project_id,
        row.project.name
      )
    end
  end
end

defmodule SanbaseWeb.GenericAdmin.Infrastructure do
  def schema_module, do: Sanbase.Model.Infrastructure

  def resource() do
    %{
      actions: [:new, :edit],
      new_fields: [:code],
      edit_fields: [:code]
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.ContractAddress do
  import Ecto.Query
  def schema_module, do: Sanbase.Project.ContractAddress

  def resource() do
    %{
      actions: [:new, :edit],
      preloads: [:project],
      new_fields: [:project, :address, :label],
      edit_fields: [:project, :address, :label],
      belongs_to_fields: %{
        project: %{
          query: from(p in Sanbase.Project, order_by: p.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "projects",
          search_fields: [:name, :slug, :ticker]
        }
      },
      funcs: %{
        project_id: &SanbaseWeb.GenericAdmin.Project.project_link/1
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.GithubOrganization do
  import Ecto.Query
  def schema_module, do: Sanbase.Project.GithubOrganization

  def resource() do
    %{
      actions: [:new, :edit],
      preloads: [:project],
      new_fields: [:project, :organization],
      edit_fields: [:project, :organization],
      belongs_to_fields: %{
        project: %{
          query: from(p in Sanbase.Project, order_by: p.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "projects",
          search_fields: [:name, :slug, :ticker]
        }
      },
      funcs: %{
        project_id: &SanbaseWeb.GenericAdmin.Project.project_link/1
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.ProjectEthAddress do
  import Ecto.Query
  def schema_module, do: Sanbase.ProjectEthAddress

  def resource() do
    %{
      actions: [:new, :edit],
      preloads: [:project],
      new_fields: [:project, :address],
      edit_fields: [:project, :address],
      belongs_to_fields: %{
        project: %{
          query: from(p in Sanbase.Project, order_by: p.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "projects",
          search_fields: [:name, :slug, :ticker]
        }
      },
      funcs: %{
        project_id: &SanbaseWeb.GenericAdmin.Project.project_link/1
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.ProjectMarketSegments do
  import Ecto.Query
  def schema_module, do: Sanbase.Project.ProjectMarketSegment

  def resource() do
    %{
      actions: [:new, :edit],
      preloads: [:project, :market_segment],
      new_fields: [:project, :market_segment],
      edit_fields: [:project, :market_segment],
      belongs_to_fields: %{
        market_segment: %{
          query: from(ms in Sanbase.Model.MarketSegment, order_by: ms.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "market_segments",
          search_fields: [:name]
        },
        project: %{
          query: from(p in Sanbase.Project, order_by: p.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "projects",
          search_fields: [:name, :slug, :ticker]
        }
      },
      funcs: %{
        project_id: &SanbaseWeb.GenericAdmin.Project.project_link/1,
        market_segment_id: &__MODULE__.market_segment_link/1
      }
    }
  end

  def market_segment_link(row) do
    SanbaseWeb.GenericAdmin.Subscription.href(
      "market_segments",
      row.market_segment_id,
      row.market_segment.name
    )
  end
end

defmodule SanbaseWeb.GenericAdmin.MarketSegments do
  import Ecto.Query
  def schema_module, do: Sanbase.Model.MarketSegment

  def resource() do
    %{
      actions: [:new, :edit],
      preloads: [:projects],
      new_fields: [:name, :type],
      edit_fields: [:name, :type]
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.SourceSlugMapping do
  import Ecto.Query
  def schema_module, do: Sanbase.Project.SourceSlugMapping

  def resource() do
    %{
      preloads: [:project],
      new_fields: [:project, :source, :slug],
      edit_fields: [:project, :source, :slug],
      collections: %{
        source: ["cryptocompare", "coinmarketcap", "binance"] |> Enum.map(&{&1, &1})
      },
      belongs_to_fields: %{
        project: %{
          query: from(p in Sanbase.Project, order_by: p.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "projects",
          search_fields: [:name, :slug, :ticker]
        }
      },
      funcs: %{
        project_id: &SanbaseWeb.GenericAdmin.Project.project_link/1
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.Ico do
  import Ecto.Query
  def schema_module, do: Sanbase.Model.Ico

  def resource() do
    %{
      preloads: [:cap_currency, :project],
      new_fields: [
        :project,
        :start_date,
        :end_date,
        :token_usd_ico_price,
        :token_eth_ico_price,
        :token_btc_ico_price,
        :tokens_issued_at_ico,
        :tokens_sold_at_ico,
        :minimal_cap_amount,
        :maximal_cap_amount,
        :contract_block_number,
        :contract_abi,
        :cap_currency,
        :comments
      ],
      edit_fields: [
        :project,
        :start_date,
        :end_date,
        :token_usd_ico_price,
        :token_eth_ico_price,
        :token_btc_ico_price,
        :tokens_issued_at_ico,
        :tokens_sold_at_ico,
        :minimal_cap_amount,
        :maximal_cap_amount,
        :contract_block_number,
        :contract_abi,
        :cap_currency,
        :comments
      ],
      field_types: %{
        comments: :text,
        contract_abi: :text
      },
      belongs_to_fields: %{
        project: %{
          query: from(p in Sanbase.Project, order_by: p.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "projects",
          search_fields: [:name, :slug, :ticker]
        },
        cap_currency: %{
          query: from(c in Sanbase.Model.Currency, order_by: c.code),
          transform: fn rows -> Enum.map(rows, &{&1.code, &1.id}) end,
          resource: "currencies",
          search_fields: [:code]
        }
      },
      funcs: %{
        project_id: &SanbaseWeb.GenericAdmin.Project.project_link/1
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.Currency do
  def schema_module, do: Sanbase.Model.Currency

  def resource() do
    %{
      actions: [:show]
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.LatestCoinmarketcapData do
  def schema_module, do: Sanbase.Model.LatestCoinmarketcapData

  def resource() do
    %{
      actions: [:show]
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.SocialVolumeQuery do
  import Ecto.Query
  def schema_module, do: Sanbase.Project.SocialVolumeQuery

  def resource() do
    %{
      actions: [:new, :edit],
      preloads: [:project],
      new_fields: [:project, :query, :autogenerated_query],
      edit_fields: [:project, :query, :autogenerated_query],
      belongs_to_fields: %{
        project: %{
          query: from(p in Sanbase.Project, order_by: p.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "projects",
          search_fields: [:name, :slug, :ticker]
        }
      },
      funcs: %{
        project_id: &SanbaseWeb.GenericAdmin.Project.project_link/1
      }
    }
  end
end
