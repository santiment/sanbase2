defmodule Sanbase.ExAdmin.Model.Project do
  use ExAdmin.Register

  import Ecto.Query, warn: false

  alias Sanbase.Model.Project
  alias Sanbase.Model.Infrastructure
  alias Sanbase.Model.MarketSegment
  alias Sanbase.Model.ProjectTransparencyStatus
  alias Sanbase.Voting.Tag

  alias Sanbase.Repo

  register_resource Sanbase.Model.Project do
    show project do
      attributes_table

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
    end

    form project do
      inputs do
        input(project, :name)
        input(project, :ticker)
        input(project, :logo_url)
        input(project, :website_link)
        input(project, :email)
        input(project, :btt_link)
        input(project, :facebook_link)
        input(project, :github_link)
        input(project, :reddit_link)
        input(project, :twitter_link)
        input(project, :whitepaper_link)
        input(project, :blog_link)
        input(project, :slack_link)
        input(project, :linkedin_link)
        input(project, :telegram_link)
        input(project, :token_address)
        input(project, :main_contract_address)
        input(project, :team_token_wallet)
        input(project, :project_transparency)

        input(
          project,
          :project_transparency_status,
          collection:
            from(pt in ProjectTransparencyStatus, order_by: pt.name) |> Sanbase.Repo.all()
        )

        input(project, :project_transparency_description)

        input(
          project,
          :market_segment,
          collection: from(m in MarketSegment, order_by: m.name) |> Sanbase.Repo.all()
        )

        input(
          project,
          :infrastructure,
          collection: from(i in Infrastructure, order_by: i.code) |> Sanbase.Repo.all()
        )

        input(project, :coinmarketcap_id)
        input(project, :token_decimals)
        input(project, :token_supply)
        input(project, :description)
      end
    end

    controller do
      # doc: https://hexdocs.pm/ex_admin/ExAdmin.Register.html#after_filter/2
      after_filter(:set_defaults, only: [:new])
      after_filter(:add_tag, only: [:create])
    end

    # Make all string filters "Contains" by default
    sidebar "", only: :index do
      panel "" do
        markup_contents do
          script type: "text/javascript" do
            """
            $(document).ready(function() {
              $("div.filter-select select option[value$=_contains]").prop('selected', true);
              $("div.filter-select select option[value$=_contains]").parent().trigger("change");
            });
            """
          end
        end
      end
    end

    # Put Actions column to the front
    sidebar " ", only: :index do
      panel "" do
        markup_contents do
          script type: "text/javascript" do
            """
            $.moveColumn = function (table, from, to) {
                var rows = $('tr', table);
                var cols;
                rows.each(function() {
                    cols = $(this).children('th, td');
                    cols.eq(from).detach().insertBefore(cols.eq(to));
                });
            }

            $(document).ready(function() {
              thact = $("table.index_table thead tr th.th-actions");
              index = $("table.index_table thead tr th").index(thact);
              table = $("table.index_table thead,tbody");
              $.moveColumn(table, index, 1);
            });
            """
          end
        end
      end
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

  defp add_tag(%Project{ticker: ticker, coinmarketcap_id: coinmarketcap_id} = _project)
       when not is_nil(ticker) and not is_nil(coinmarketcap_id) do
    %Tag{name: ticker}
    |> Tag.changeset()
    |> Repo.insert()
  end

  defp add_tag(%Project{}), do: :ok
end
