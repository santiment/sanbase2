defmodule Sanbase.ExternalServices.IcoSpreadsheet do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://sheets.googleapis.com/v4/spreadsheets/"
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Compression
  plug Tesla.Middleware.Logger

  alias Sanbase.ExternalServices.IcoSpreadsheet.IcoSpreadsheetRow

  def get_project_data(document_id, api_key, project_names) when is_list(project_names) do
    ico_data_url(document_id, api_key)
    |> get()
    |> case do
      %{status: 200, body: %{"values" => data}} ->
        column_indices = hd(data) |> parse_header_row()

        tl(data)
        |> filter_value_rows(column_indices, project_names)
        |> parse_value_rows(column_indices)
    end
  end

  defp ico_data_url(document_id, api_key) do
    "#{document_id}/values/ICOs?valueRenderOption=UNFORMATTED_VALUE&key=#{api_key}"
  end

  # TODO: get column indices from the header row
  defp parse_header_row(header_row) do
    IcoSpreadsheetRow.get_column_indices
  end

  defp filter_value_rows(value_rows, column_indices, project_names) do
    Enum.filter(value_rows, fn(value_row) ->
      project_name = get_value!(value_row, column_indices.project_name)

      !is_nil(project_name) and
        (Enum.empty?(project_names) or Enum.member?(project_names, project_name))
    end)
  end

  defp parse_value_rows(value_rows, column_indices) do
    value_rows
    |> Enum.map(&parse_value_row(&1, column_indices))
  end

  defp parse_value_row(value_row, column_indices) do
    res = column_indices
    |> Enum.map(&parse_value(value_row, &1))
    |> Enum.into(%{})
    |> handle_wallets()

    struct!(IcoSpreadsheetRow, res)
  end

  defp get_value!(value_row, column_index) do
    value = Enum.fetch(value_row, column_index)
    case value do
      {:ok, v} when v in ["", "n/a", "N/A", "-"] -> nil
      {:ok, v} -> v
      _ -> nil
    end
  end

  defp parse_value(value_row, {column, index}) do
    value = get_value!(value_row, index)
    value =
    case column do
      c when c in [:ico_start_date, :ico_end_date, :btt_date, :twitter_joindate] ->
        parse_date(value)
      c when c in [:tokens_issued_at_ico, :tokens_sold_at_ico, :tokens_team, :ico_contributors, :team_website, :team_linkedin_available, :team_dev_people, :team_business_people, :team_advisors, :advisor_linkedin_available, :github_commits, :github_contributors, :wp_authors, :wp_pages, :wp_citations, :btt_total_reads, :btt_post_until_icostart, :btt_post_until_icoend, :btt_posts_total, :twitter_tweets, :twitter_follower, :twitter_following, :twitter_likes, :facebook_likes, :reddit_subscribers] ->
        parse_int(value)
      c when c in [:usd_btc_icoend, :funds_raised_btc, :usd_eth_icoend, :highest_bonus_percent_for_ico, :percent_tokens_for_bounties, :minimal_cap_amount, :maximal_cap_amount, :avno_linkedin_network_team, :av_no_linkedin_network_advisors] ->
        parse_decimal(value)
      c when c in [:bounty_campaign, :minimal_cap_archived, :maximal_cap_archived, :team_real_names, :team_pics_availabe, :open_source, :wp_available] ->
        parse_boolean(value)
      c when c in [:ico_currencies, :team_country_origins] ->
        parse_comma_delimited(value)
      _ -> value
    end

    {column, value}
  end

  defp parse_int(value) do
    if(is_binary(value)) do
      case Integer.parse(value) do
        {result, _} -> result
        _ -> #TODO: return error
          IO.write("parse_int error: ")
          IO.inspect value
          nil
      end
    else
      value
    end
  end

  defp parse_decimal(value) do
    if(is_binary(value)) do
      case Decimal.parse(value) do
        {:ok, result} -> result
        _ -> #TODO: return error
          IO.write("parse_decimal error: ")
          IO.inspect value
          nil
      end
    else
      value
    end
  end

  defp parse_boolean(value) do
    value = if(is_binary(value)) do String.downcase(value) else value end

    case value do
      v when v in ["yes", "true", 1] -> true
      v when v in ["no", "false", 0] -> false
      nil -> nil
      _ -> #TODO: return error
        IO.write("parse_boolean error: ")
        IO.inspect value
        nil
    end
  end

  defp parse_date(value) do
    if(!is_nil(value)) do
      if(is_integer(value)) do
        #the -2 is to account for an Excel bug (search in internet)
        Date.add(~D[1900-01-01], value - 2)
      else
        #TODO: return error
        IO.write("parse_date error: ")
        IO.inspect value
        nil
      end
    else
      nil
    end
  end

  defp parse_comma_delimited(value) do
    if(!is_nil(value)) do
      if(is_binary(value)) do
        value
        |> String.split(",")
        |> Enum.map(&String.trim(&1))
        |> Enum.filter(&(String.length(&1) > 0))
      else
        #TODO: return error
        IO.write("parse_comma_delimited error: ")
        IO.inspect value
        nil
      end
    else
      []
    end
  end

  defp handle_wallets(parsed_value_row) do
    parsed_value_row
    |> Map.put(:eth_wallets, remove_nils([parsed_value_row.eth_wallet]))
    |> Map.put(:btc_wallets, remove_nils([parsed_value_row.btc_wallet, parsed_value_row.btc_wallet2, parsed_value_row.btc_wallet3, parsed_value_row.btc_wallet4, parsed_value_row.btc_wallet5]))
    |> Map.drop([:eth_wallet, :btc_wallet, :btc_wallet2, :btc_wallet3, :btc_wallet4, :btc_wallet5])
  end

  defp remove_nils(list) when is_list(list) do
    Enum.filter(list, &(!is_nil(&1)))
  end
end
