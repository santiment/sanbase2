defmodule SanbaseWeb.ExAdmin.Project do
  use ExAdmin.Register

  import Ecto.Query, warn: false

  alias Sanbase.Tag
  alias Sanbase.Project
  alias Sanbase.Model.Infrastructure

  alias Sanbase.Repo

  register_resource Sanbase.Project do
    filter([
      :name,
      :ticker,
      :slug,
      :website_link,
      :token_decimals,
      :infrastructure,
      :is_hidden
    ])

    index do
      column(:id, link: true)
      column(:ticker)
      column(:name)
      column(:slug)
      column(:website_link)
      column(:infrastructure)
      column(:token_decimals)
      column(:is_hidden)
    end

    show project do
      attributes_table(all: true)

      panel "Contract Addresses" do
        markup_contents do
          a ".btn .btn-primary",
            href: "/admin/contract_addresses/new?project_id=" <> to_string(project.id) do
            "New Contract Address"
          end
        end

        table_for Sanbase.Repo.preload(project, [:contract_addresses]).contract_addresses do
          column(:address, link: true)
          column(:label)
        end
      end

      panel "Github Organizations" do
        markup_contents do
          a ".btn .btn-primary",
            href: "/admin/github_organizations/new?project_id=" <> to_string(project.id) do
            "New Github Organization"
          end
        end

        table_for Sanbase.Repo.preload(project, [:github_organizations]).github_organizations do
          column(:organization, link: true)
        end
      end

      panel "Market Segments" do
        markup_contents do
          a ".btn .btn-primary",
            href: "/admin/project_market_segments/new?project_id=" <> to_string(project.id) do
            "New Market Segment"
          end
        end

        table_for Sanbase.Repo.preload(project, [:market_segments]).market_segments do
          column(:name, link: true)
        end
      end

      panel "Slug Source Mappings" do
        markup_contents do
          a ".btn .btn-primary",
            href: "/admin/source_slug_mappings/new?project_id=" <> to_string(project.id) do
            "New Slug Source Mapping"
          end
        end

        table_for project.source_slug_mappings do
          column(:source)
          column(:slug)
        end
      end

      panel "ETH Addresses" do
        markup_contents do
          a ".btn .btn-primary",
            href: "/admin/project_eth_addresses/new?project_id=" <> to_string(project.id) do
            "New ETH Address"
          end
        end

        table_for project.eth_addresses do
          column(:id, link: true)
          column(:address)
        end
      end

      panel "BTC Addresses" do
        markup_contents do
          a ".btn .btn-primary",
            href: "/admin/project_btc_addresses/new?project_id=" <> to_string(project.id) do
            "New BTC Address"
          end
        end

        table_for project.btc_addresses do
          column(:id, link: true)
          column(:address)
        end
      end

      panel "ICO Events" do
        markup_contents do
          a ".btn .btn-primary", href: "/admin/icos/new?project_id=" <> to_string(project.id) do
            "New ICO"
          end
        end

        table_for Sanbase.Repo.preload(project.icos, [:cap_currency, ico_currencies: [:currency]]) do
          column(:id, link: true)
          column(:start_date)
          column(:end_date)
          column(:token_usd_ico_price)
          column(:token_eth_ico_price)
          column(:token_btc_ico_price)
          column(:tokens_issued_at_ico)
          column(:tokens_sold_at_ico)
          column(:minimal_cap_amount)
          column(:maximal_cap_amount)
          column(:comments)
          column(:cap_currency)

          column("Currency used and collected amount", [], fn ico ->
            ico.ico_currencies
            |> Enum.map(fn ic -> "#{ic.currency.code}: #{ic.amount}" end)
            |> Enum.join("<br/>")
          end)
        end
      end

      panel "Latest Coinmarketcap Data" do
        list_cmc_data =
          case Sanbase.Repo.preload(project, [:latest_coinmarketcap_data]).latest_coinmarketcap_data do
            nil -> []
            elem -> [elem]
          end

        table_for list_cmc_data do
          column(:coinmarketcap_id)
          column(:coinmarketcap_integer_id)
          column(:rank)
          column(:price_usd)
          column(:price_btc)
          column(:volume_usd)
          column(:market_cap_usd)
          column(:available_supply)
          column(:total_supply)
          column(:logo_updated_at)
          column(:update_time)
        end
      end
    end

    form project do
      inputs do
        input(project, :name)
        input(project, :ticker)
        input(project, :slug)
        input(project, :description)
        input(project, :long_description, type: :text)
        input(project, :token_supply)

        input(
          project,
          :infrastructure,
          collection: from(i in Infrastructure, order_by: i.code) |> Sanbase.Repo.all()
        )

        input(project, :token_decimals)

        input(project, :is_hidden)
        input(project, :telegram_chat_id)
        input(project, :logo_url)
        input(project, :dark_logo_url)
        input(project, :email)

        input(project, :blog_link)
        input(project, :btt_link)
        input(project, :facebook_link)
        input(project, :linkedin_link)
        input(project, :reddit_link)
        input(project, :slack_link)
        input(project, :discord_link)
        input(project, :telegram_link)
        input(project, :twitter_link)
        input(project, :website_link)
        input(project, :whitepaper_link)
      end
    end

    controller do
      # doc: https://hexdocs.pm/ex_admin/ExAdmin.Register.html#after_filter/2
      after_filter(:set_defaults, only: [:new])
      after_filter(:add_tag, only: [:create])
    end
  end

  def set_defaults(conn, params, resource, :new) do
    resource =
      resource
      |> set_infrastructure_default()

    {conn, params, resource}
  end

  def add_tag(conn, params, resource, :create) do
    resource
    |> add_tag()

    {conn, params, resource}
  end

  defp set_infrastructure_default(%Project{infrastructure_id: nil} = project) do
    infrastructure = Infrastructure.get("ETH")

    case infrastructure do
      %Infrastructure{id: id} -> Map.put(project, :infrastructure_id, id)
      _ -> project
    end
  end

  defp set_infrastructure_default(%Project{} = project), do: project

  defp add_tag(%Project{ticker: ticker, slug: slug} = _project)
       when not is_nil(ticker) and not is_nil(slug) do
    %Tag{name: ticker}
    |> Tag.changeset()
    |> Repo.insert()
  end

  defp add_tag(%Project{}), do: :ok
end
