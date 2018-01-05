defmodule Sanbase.DbScripts.ImportIcoSpreadsheet do
  import Ecto.Query, warn: false
  alias Sanbase.Repo

  require Logger

  alias Sanbase.ExternalServices.IcoSpreadsheet.IcoSpreadsheetRow

  alias Sanbase.Model.{Project, ProjectEthAddress, ProjectBtcAddress, Ico, MarketSegment, Infrastructure, ProjectTransparencyStatus}
  alias Sanbase.Model.Currency
  alias Sanbase.Model.IcoCurrencies

  def import(ico_spreadsheet) when is_list(ico_spreadsheet) do
    Logger.info("Starting ICO spreadsheet import...")
    ico_spreadsheet
    |> Enum.reverse()
    |> Enum.uniq_by(fn row -> row.project_name end)
    |> Enum.reverse()
    |> put_presales_in_front()
    |> Enum.each(&import_row(&1))
    Logger.info("Finished ICO spreadsheet import.")
  end

  # The common project data in the main ICO row is with higher priority than the presale => put the presale to the front
  defp put_presales_in_front(ico_spreadsheet) do
    {presales, main_icos} = Enum.split_with(ico_spreadsheet, fn(row) ->
      row.project_name
      |> String.downcase()
      |> String.trim()
      |> String.ends_with?(" (presale)")
    end)

    presales
    |> adjust_presales_project_names()
    |> Enum.concat(main_icos)
  end

  # Make the project names of the 2 rows (presale and main) the same so they are inserted as 2 icos of the same project
  defp adjust_presales_project_names(ico_spreadsheet) do
    Enum.map(ico_spreadsheet, fn(row) ->
      project_name = row.project_name
      |> String.trim()
      |> String.replace_suffix(" (presale)", "")
      |> String.replace_suffix(" (Presale)", "")

      Map.put(row, :project_name, project_name)
    end)
  end

  defp import_row(ico_spreadsheet_row = %IcoSpreadsheetRow{}) do
    ico_spreadsheet_row = ico_spreadsheet_row
    |> set_infrastructure_default()

    Repo.transaction(fn ->
      project = insert_or_update_project(ico_spreadsheet_row)

      project
      |> insert_or_update_ico(ico_spreadsheet_row)
      |> insert_or_update_ico_currencies(ico_spreadsheet_row)

      project
      |> insert_or_update_eth_wallets(ico_spreadsheet_row)

      project
      |> insert_or_update_btc_wallets(ico_spreadsheet_row)
    end)
  end

  defp insert_or_update_project(ico_spreadsheet_row) do
    fill_project(ico_spreadsheet_row)
    |> put_assoc_if_not_nil(:market_segment, ensure_market_segment(ico_spreadsheet_row.market_segment))
    |> put_assoc_if_not_nil(:infrastructure, ensure_infrastructure(ico_spreadsheet_row.infrastructure))
    |> put_assoc_if_not_nil(:project_transparency_status, ensure_project_transparency_status(ico_spreadsheet_row.project_transparency))
    |> Repo.insert_or_update!()
    |> Repo.preload([:eth_addresses, :btc_addresses, :market_segment, :infrastructure, :project_transparency_status, {:icos, [{:ico_currencies, [:ico, :currency]}, :cap_currency]}])
  end

  defp fill_project(ico_spreadsheet_row) do
    values = %{
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
      project_transparency: is_project_transparency?(ico_spreadsheet_row.project_transparency),
      team_token_wallet: ico_spreadsheet_row.team_token_wallet
      }
    |> remove_map_nils()

    ensure_project(ico_spreadsheet_row.project_name)
    |> Project.changeset(values)
  end

  defp is_project_transparency?(nil), do: false
  defp is_project_transparency?(_), do: true

  defp insert_or_update_ico(project, ico_spreadsheet_row) do
    fill_ico(project, ico_spreadsheet_row)
    |> put_assoc_if_not_nil(:cap_currency, ensure_currency(ico_spreadsheet_row.cap_currency))
    |> Repo.insert_or_update!()
  end

  defp fill_ico(project, ico_spreadsheet_row) do
    values = %{
      project_id: project.id,
      start_date: ico_spreadsheet_row.ico_start_date,
      end_date: ico_spreadsheet_row.ico_end_date,
      tokens_issued_at_ico: ico_spreadsheet_row.tokens_issued_at_ico,
      tokens_sold_at_ico: ico_spreadsheet_row.tokens_sold_at_ico,
      funds_raised_btc: ico_spreadsheet_row.funds_raised_btc,
      funds_raised_usd: ico_spreadsheet_row.funds_raised_usd,
      funds_raised_eth: ico_spreadsheet_row.funds_raised_eth,
      minimal_cap_amount: ico_spreadsheet_row.minimal_cap_amount,
      maximal_cap_amount: ico_spreadsheet_row.maximal_cap_amount,
      main_contract_address: ico_spreadsheet_row.ico_main_contract_address,
      comments: ico_spreadsheet_row.comments
      }
    |> remove_map_nils()

    ensure_ico(project, ico_spreadsheet_row)
    |> Ico.changeset(values)
  end

  defp insert_or_update_ico_currencies(_ico, %IcoSpreadsheetRow{ico_currencies: nil}), do: nil
  defp insert_or_update_ico_currencies(ico, %IcoSpreadsheetRow{ico_currencies: ico_currencies}) do
    currencies = ensure_currencies(ico_currencies)
    |> Enum.map(fn(currency) ->
      Ecto.Changeset.change(currency)
      |> Repo.insert_or_update!()
    end)

    Enum.each(currencies, fn(currency) ->
      ensure_ico_currency(ico, currency)
      |> Repo.insert_or_update!()
    end)

    currency_ids = Enum.map(currencies, &Map.fetch!(&1, :id))
    Repo.delete_all(from c in IcoCurrencies, where: c.ico_id == ^ico.id and c.currency_id not in ^currency_ids)
  end

  defp insert_or_update_eth_wallets(_project, %IcoSpreadsheetRow{eth_wallets: nil}), do: nil
  defp insert_or_update_eth_wallets(project, %IcoSpreadsheetRow{eth_wallets: eth_wallets}) do
    wallets = ensure_eth_wallets(project, eth_wallets)
    |> Enum.map(fn(wallet) ->
      Ecto.Changeset.change(wallet)
      |> Repo.insert_or_update!()
    end)
  end

  defp insert_or_update_btc_wallets(_project, %IcoSpreadsheetRow{btc_wallets: nil}), do: nil
  defp insert_or_update_btc_wallets(project, %IcoSpreadsheetRow{btc_wallets: btc_wallets}) do
    wallets = ensure_btc_wallets(project, btc_wallets)
    |> Enum.map(fn(wallet) ->
      Ecto.Changeset.change(wallet)
      |> Repo.insert_or_update!()
    end)
  end

  defp ensure_project(project_name) do
    Repo.get_by(Project, name: project_name)
    |> Repo.preload([:eth_addresses, :btc_addresses, :market_segment, :infrastructure, :project_transparency_status, {:icos, [{:ico_currencies, [:ico, :currency]}, :cap_currency]}])
    |> case do
      result = %Project{} -> result
      nil -> %Project{}
    end
  end

  defp ensure_ico(project, ico_spreadsheet_row) do
    project.icos
    |> Enum.find(fn(ico) ->
      (is_nil(ico_spreadsheet_row.ico_start_date) and is_nil(ico.start_date))
      or (!is_nil(ico_spreadsheet_row.ico_start_date)
          and !is_nil(ico.start_date)
          and Ecto.Date.compare(ico.start_date, Ecto.Date.cast!(ico_spreadsheet_row.ico_start_date)) == :eq)
    end)
    |> case do
      %Ico{} = result -> result
      _ -> %Ico{}
    end
  end

  defp ensure_market_segment(nil), do: nil
  defp ensure_market_segment(market_segment_name) do
    Repo.get_by(MarketSegment, name: market_segment_name)
    |> case do
      result = %MarketSegment{} -> result
      nil ->
        %MarketSegment{}
        |> MarketSegment.changeset(%{name: market_segment_name})
    end
  end

  defp ensure_infrastructure(nil), do: nil
  defp ensure_infrastructure(infrastructure_code) do
    Repo.get_by(Infrastructure, code: infrastructure_code)
    |> case do
      result = %Infrastructure{} -> result
      nil ->
        %Infrastructure{}
        |> Infrastructure.changeset(%{code: infrastructure_code})
    end
  end

  defp ensure_project_transparency_status(nil), do: nil
  defp ensure_project_transparency_status(project_transparency_status_name) do
    Repo.get_by(ProjectTransparencyStatus, name: project_transparency_status_name)
    |> case do
      result = %ProjectTransparencyStatus{} -> result
      nil ->
        %ProjectTransparencyStatus{}
        |> ProjectTransparencyStatus.changeset(%{name: project_transparency_status_name})
    end
  end

  defp ensure_currencies(currency_codes) do
    currency_codes
    |> Enum.map(&ensure_currency(&1))
  end

  defp ensure_currency(nil), do: nil
  defp ensure_currency(currency_code) do
    Repo.get_by(Currency, code: currency_code)
    |> case do
      result = %Currency{} -> result
      nil ->
        %Currency{}
        |> Currency.changeset(%{code: currency_code})
    end
  end

  defp ensure_ico_currency(ico, currency) do
    Repo.get_by(IcoCurrencies, ico_id: ico.id, currency_id: currency.id)
    |> Repo.preload([:ico, :currency])
    |> case do
      result = %IcoCurrencies{} -> result
      nil -> %IcoCurrencies{}
    end
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:ico, ico)
    |> Ecto.Changeset.put_assoc(:currency, currency)
  end

  defp ensure_eth_wallets(project, wallet_addresses) do
    wallet_addresses
    |> Enum.map(&ensure_eth_wallet(project, &1))
  end

  defp ensure_eth_wallet(project, nil), do: nil
  defp ensure_eth_wallet(project, wallet_address) do
    Repo.get_by(ProjectEthAddress, address: wallet_address)
    |> Repo.preload([:project])
    |> case do
      result = %ProjectEthAddress{} ->
        result
        |> ProjectEthAddress.changeset(%{project_id: project.id, project_transparency: project.project_transparency})
      nil ->
        %ProjectEthAddress{}
        |> ProjectEthAddress.changeset(%{project_id: project.id, address: wallet_address, project_transparency: project.project_transparency})
    end
  end

  defp ensure_btc_wallets(project, wallet_addresses) do
    wallet_addresses
    |> Enum.map(&ensure_btc_wallet(project, &1))
  end

  defp ensure_btc_wallet(project, nil), do: nil
  defp ensure_btc_wallet(project, wallet_address) do
    Repo.get_by(ProjectBtcAddress, address: wallet_address)
    |> Repo.preload([:project])
    |> case do
      result = %ProjectBtcAddress{} ->
        result
        |> ProjectBtcAddress.changeset(%{project_id: project.id, project_transparency: project.project_transparency})
      nil ->
        %ProjectBtcAddress{}
        |> ProjectBtcAddress.changeset(%{project_id: project.id, address: wallet_address, project_transparency: project.project_transparency})
    end
  end

  defp set_infrastructure_default(ico_spreadsheet_row = %IcoSpreadsheetRow{infrastructure: nil}) do
    Map.put(ico_spreadsheet_row, :infrastructure, "ETH")
  end
  defp set_infrastructure_default(%IcoSpreadsheetRow{}=ico_spreadsheet_row), do: ico_spreadsheet_row

  defp put_assoc_if_not_nil(changeset, _name, nil), do: changeset
  defp put_assoc_if_not_nil(changeset, name, value) do
    Ecto.Changeset.put_assoc(changeset, name, value)
  end

  defp remove_map_nils(%{} = map) do
    map
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> Enum.into(%{})
  end
end
