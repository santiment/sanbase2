defmodule Sanbase.DbScripts.ImportIcoSpreadsheet do
  import Ecto.Query, warn: false
  alias Sanbase.Repo

  alias Sanbase.ExternalServices.IcoSpreadsheet.IcoSpreadsheetRow

  # alias Sanbase.Model.{Project, ProjectEthAddress, ProjectBtcAddress, Btt, Facebook, Github, Ico, Reddit, Team, Twitter, Whitepaper, MarketSegment, Infrastructure, Country, Prices}
  # alias Sanbase.Model.Currency

  def import(ico_spreadsheet) when is_list(ico_spreadsheet) do
    # ico_spreadsheet
    # |> Enum.each(&import_row(&1))
  end

  # # TODO: import each row in transaction
  # # TODO: log & return errors
  # defp import_row(ico_spreadsheet_row = %IcoSpreadsheetRow{}) do
  #   project = fill_project(ico_spreadsheet_row)
  #   |> Ecto.Changeset.put_assoc(:market_segment, ensure_market_segment(ico_spreadsheet_row.market_segment))
  #   |> Ecto.Changeset.put_assoc(:infrastructure, ensure_infrastructure(ico_spreadsheet_row.infrastructure))
  #   |> Ecto.Changeset.put_assoc(:geolocation_country, ensure_country(ico_spreadsheet_row.geolocation))
  #   |> Repo.insert_or_update!()
  #
  #   fill_ico(project, ico_spreadsheet_row)
  #   |> Ecto.Changeset.put_assoc(:currencies, ensure_currencies(ico_spreadsheet_row.ico_currencies))
  #   |> Repo.insert_or_update!()
  # end
  #
  # defp fill_project(ico_spreadsheet_row) do
  #   ensure_project(ico_spreadsheet_row.project_name)
  #   |> Project.changeset(%{
  #     name: ico_spreadsheet_row.project_name,
  #     ticker: ico_spreadsheet_row.ticker,
  #     geolocation_city: ico_spreadsheet_row.geolocation_city,
  #     website_link: ico_spreadsheet_row.website_link,
  #     open_source: ico_spreadsheet_row.open_source
  #     })
  # end
  #
  # defp fill_ico(project, ico_spreadsheet_row) do
  #   ensure_ico(project)
  #   |> Ico.changeset(%{
  #     project_id: project.id,
  #     start_date: ico_spreadsheet_row.ico_start_date,
  #     end_date: ico_spreadsheet_row.ico_start_date,
  #     tokens_issued_at_ico: ico_spreadsheet_row.tokens_issued_at_ico,
  #     tokens_sold_at_ico: ico_spreadsheet_row.tokens_sold_at_ico,
  #     tokens_team: ico_spreadsheet_row.tokens_team,
  #     usd_btc_icoend: ico_spreadsheet_row.usd_btc_icoend,
  #     funds_raised_btc: ico_spreadsheet_row.funds_raised_btc,
  #     usd_eth_icoend: ico_spreadsheet_row.usd_eth_icoend,
  #     ico_contributors: ico_spreadsheet_row.ico_contributors,
  #     highest_bonus_percent_for_ico: ico_spreadsheet_row.highest_bonus_percent_for_ico,
  #     bounty_campaign: ico_spreadsheet_row.bounty_campaign,
  #     percent_tokens_for_bounties: ico_spreadsheet_row.percent_tokens_for_bounties,
  #     minimal_cap_amount: ico_spreadsheet_row.minimal_cap_amount,
  #     minimal_cap_archived: ico_spreadsheet_row.minimal_cap_archived,
  #     maximal_cap_amount: ico_spreadsheet_row.maximal_cap_amount,
  #     maximal_cap_archived: ico_spreadsheet_row.maximal_cap_archived
  #     })
  # end
  #
  # defp ensure_project(project_name) do
  #   Repo.get_by(Project, name: project_name)
  #   |> Repo.preload([:eth_addresses, :btc_addresses, :market_segment, :infrastructure, :geolocation_country, :btt, :facebook, :github, {:ico, [:currencies]}, :reddit, :team, :twitter, :whitepaper])
  #   |> case do
  #     result = %Project{} -> result
  #     nil -> %Project{}
  #   end
  # end
  #
  # defp ensure_market_segment(market_segment_name) do
  #   if(!is_nil(market_segment_name)) do
  #     Repo.get_by(MarketSegment, name: market_segment_name)
  #     |> case do
  #       result = %MarketSegment{} -> result
  #       nil ->
  #         %MarketSegment{}
  #         |> MarketSegment.changeset(%{name: market_segment_name})
  #     end
  #   else
  #     nil
  #   end
  # end
  #
  # defp ensure_infrastructure(infrastructure_code) do
  #   if(!is_nil(infrastructure_code)) do
  #     Repo.get_by(Infrastructure, code: infrastructure_code)
  #     |> case do
  #       result = %Infrastructure{} -> result
  #       nil ->
  #         %Infrastructure{}
  #         |> Infrastructure.changeset(%{code: infrastructure_code})
  #     end
  #   else
  #     nil
  #   end
  # end
  #
  # defp ensure_country(country_code) do
  #   if(!is_nil(country_code)) do
  #     Repo.get_by(Country, code: country_code)
  #     |> case do
  #       result = %Country{} -> result
  #       nil ->
  #         %Country{}
  #         |> Country.changeset(%{code: country_code})
  #     end
  #   else
  #     nil
  #   end
  # end
  #
  # defp ensure_ico(project) do
  #   case project do
  #     %{ico: result = %Ico{}} -> result
  #     _ -> %Ico{}
  #   end
  # end
  #
  # defp ensure_currencies(currency_codes) do
  #   currency_codes
  #   |> Enum.map(&ensure_currency(&1))
  # end
  #
  # defp ensure_currency(currency_code) do
  #   if(!is_nil(currency_code)) do
  #     Repo.get_by(Currency, code: currency_code)
  #     |> case do
  #       result = %Currency{} -> result
  #       nil ->
  #         %Currency{}
  #         |> Currency.changeset(%{code: currency_code})
  #     end
  #   else
  #     nil
  #   end
  # end
end
