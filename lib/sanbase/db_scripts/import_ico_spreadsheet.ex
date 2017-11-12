defmodule Sanbase.DbScripts.ImportIcoSpreadsheet do
  import Ecto.Query, warn: false
  alias Sanbase.Repo

  alias Sanbase.ExternalServices.IcoSpreadsheet.IcoSpreadsheetRow

  alias Sanbase.Model.{Project, ProjectEthAddress, ProjectBtcAddress, Ico, MarketSegment, Infrastructure}
  alias Sanbase.Model.Currency

  def import(ico_spreadsheet) when is_list(ico_spreadsheet) do
    ico_spreadsheet
    |> Enum.each(&import_row(&1))
  end

  # TODO: import each row in transaction
  # TODO: log & return errors
  defp import_row(ico_spreadsheet_row = %IcoSpreadsheetRow{}) do
    project = fill_project(ico_spreadsheet_row)
    |> Ecto.Changeset.put_assoc(:market_segment, ensure_market_segment(ico_spreadsheet_row.market_segment))
    |> Ecto.Changeset.put_assoc(:infrastructure, ensure_infrastructure(ico_spreadsheet_row.infrastructure))
    |> Repo.insert_or_update!()

    fill_ico(project, ico_spreadsheet_row)
    |> Ecto.Changeset.put_assoc(:currencies, ensure_currencies(ico_spreadsheet_row.ico_currencies))
    |> Ecto.Changeset.put_assoc(:cap_currency, ensure_currency(ico_spreadsheet_row.cap_currency))
    |> Repo.insert_or_update!()
  end

  defp fill_project(ico_spreadsheet_row) do
    ensure_project(ico_spreadsheet_row.project_name)
    |> Project.changeset(%{
      name: ico_spreadsheet_row.project_name,
      ticker: ico_spreadsheet_row.ticker,
      website_link: ico_spreadsheet_row.website_link,
      btt_link: ico_spreadsheet_row.btt_link,
      facebook_link: ico_spreadsheet_row.facebook_link,
      github_link: ico_spreadsheet_row.github_link,
      reddit_link: ico_spreadsheet_row.reddit_link,
      twitter_link: ico_spreadsheet_row.twitter_link,
      whitepaper_link: ico_spreadsheet_row.wp_link,
      blog_link: ico_spreadsheet_row.blog_link,
      slack_link: ico_spreadsheet_row.slack_link,
      linkedin_link: ico_spreadsheet_row.linkedin_link,
      telegram_link: ico_spreadsheet_row.telegram_link,
      project_transparency: ico_spreadsheet_row.project_transparency,
      team_token_wallet: ico_spreadsheet_row.team_token_wallet
      })
  end

  defp fill_ico(project, ico_spreadsheet_row) do
    ensure_ico(project)
    |> Ico.changeset(%{
      project_id: project.id,
      start_date: ico_spreadsheet_row.ico_start_date,
      end_date: ico_spreadsheet_row.ico_start_date,
      tokens_issued_at_ico: ico_spreadsheet_row.tokens_issued_at_ico,
      tokens_sold_at_ico: ico_spreadsheet_row.tokens_sold_at_ico,
      usd_btc_icoend: ico_spreadsheet_row.usd_btc_icoend,
      funds_raised_btc: ico_spreadsheet_row.funds_raised_btc,
      usd_eth_icoend: ico_spreadsheet_row.usd_eth_icoend,
      minimal_cap_amount: ico_spreadsheet_row.minimal_cap_amount,
      maximal_cap_amount: ico_spreadsheet_row.maximal_cap_amount,
      main_contract_address: ico_spreadsheet_row.ico_main_contract_address,
      comments: ico_spreadsheet_row.comments,
      })
  end

  defp ensure_project(project_name) do
    Repo.get_by(Project, name: project_name)
    |> Repo.preload([:eth_addresses, :btc_addresses, :market_segment, :infrastructure, {:ico, [:currencies, :cap_currency]}])
    |> case do
      result = %Project{} -> result
      nil -> %Project{}
    end
  end

  defp ensure_market_segment(market_segment_name) when not is_nil(market_segment_name) do
    Repo.get_by(MarketSegment, name: market_segment_name)
    |> case do
      result = %MarketSegment{} -> result
      nil ->
        %MarketSegment{}
        |> MarketSegment.changeset(%{name: market_segment_name})
    end
  end

  defp ensure_market_segment(_), do: nil

  defp ensure_infrastructure(infrastructure_code) when not is_nil(infrastructure_code) do
    Repo.get_by(Infrastructure, code: infrastructure_code)
    |> case do
      result = %Infrastructure{} -> result
      nil ->
        %Infrastructure{}
        |> Infrastructure.changeset(%{code: infrastructure_code})
    end
  end

  defp ensure_infrastructure(_), do: nil

  defp ensure_ico(project) do
    case project do
      %{ico: result = %Ico{}} -> result
      _ -> %Ico{}
    end
  end

  defp ensure_currencies(currency_codes) do
    currency_codes
    |> Enum.map(&ensure_currency(&1))
  end

  defp ensure_currency(currency_code) when not is_nil(currency_code) do
    Repo.get_by(Currency, code: currency_code)
    |> case do
      result = %Currency{} -> result
      nil ->
        %Currency{}
        |> Currency.changeset(%{code: currency_code})
    end
  end

  defp ensure_currency(_), do: nil
end
