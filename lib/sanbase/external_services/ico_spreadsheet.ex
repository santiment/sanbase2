defmodule Sanbase.ExternalServices.IcoSpreadsheet do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://sheets.googleapis.com/v4/spreadsheets/"
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Compression
  plug Tesla.Middleware.Logger

  # TODO: spreadsheet_id & api key should be fetched from env variables
  @spreadsheet_id "INSERT_SPREADSHEET_ID"
  @api_key "INSERT_API_KEY"

  def get_project_data!(project_names) when is_list(project_names) do
    ico_data_url()
    |> get()
    |> case do
      %{status: 200, body: %{"values" => data}} ->
        column_indices = hd(data) |> parse_header_row()

        tl(data)
        |> filter_value_rows(column_indices, project_names)
        |> parse_value_rows(column_indices)
    end
  end

  defp ico_data_url do
    "#{@spreadsheet_id}/values/ICOs?valueRenderOption=UNFORMATTED_VALUE&key=#{@api_key}"
  end

  # TODO: get column indices from the header row
  defp parse_header_row(header_row) do
    %{
      project_name: 1,
      ico_start_date: 15,
      ico_end_date: 16,
      tokens_issued_at_ico: 22,
      tokens_sold_at_ico: 23,
      tokens_team: 24,
      usd_btc_icoend: 28,
      funds_raised_btc: 29,
      usd_eth_icoend: 30,
      ico_currencies: 32,
      ico_contributors: 35,
      highest_bonus_percent_for_ico: 36,
      bounty_campaign: 37,
      percent_tokens_for_bounties: 38,
      minimal_cap_amount: 40,
      minimal_cap_archived: 41,
      maximal_cap_amount: 43,
      maximal_cap_archived: 44,
      market_segment: 45,
      infrastructure: 52,
      team_website: 63,
      team_linkedin_available: 64,
      avno_linkedin_network_team: 65,
      team_country_origins: 67,
      team_dev_people: 71,
      team_business_people: 73,
      team_real_names: 75,
      team_pics_availabe: 76,
      team_advisors: 78,
      advisor_linkedin_available: 79,
      av_no_linkedin_network_advisors: 80,
      geolocation: 81,
      geolocation_city: 85,
      website_link: 86,
      open_source: 95,
      github_link: 96,
      github_commits: 97,
      github_contributors: 98,
      wp_available: 99,
      wp_link: 100,
      wp_authors: 101,
      wp_pages: 102,
      wp_citations: 103,
      btt_link: 105,
      btt_date: 106,
      btt_total_reads: 108,
      btt_post_until_icostart: 110,
      btt_post_until_icoend: 111,
      btt_posts_total: 112,
      twitter_link: 115,
      twitter_joindate: 116,
      twitter_tweets: 117,
      twitter_follower: 119,
      twitter_following: 121,
      twitter_likes: 124,
      facebook_link: 126,
      facebook_likes: 127,
      reddit_link: 129,
      reddit_subscribers: 147
    }
  end

  defp filter_value_rows(value_rows, column_indices, project_names) do
    Enum.filter(value_rows, fn(value_row) ->
      project_name = get_value!(value_row, column_indices.project_name)
      Enum.member?(project_names, project_name)
    end)
  end

  defp parse_value_rows(value_rows, column_indices) do
    value_rows
    |> Enum.map(&parse_value_row(&1, column_indices))
  end

  defp parse_value_row(value_row, column_indices) do
    column_indices
    |> Enum.map(&parse_value(value_row, &1))
    |> Enum.into(%{})
  end

  defp get_value!(value_row, column_index) do
    value = Enum.fetch!(value_row, column_index)
    case value do
      v when v in ["", "n/a", "N/A"] -> nil
      _ -> value
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
        # _ -> nil #TODO: return error
      end
    else
      value
    end
  end

  defp parse_decimal(value) do
    if(is_binary(value)) do
      case Decimal.parse(value) do
        {:ok, result} -> result
        # _ -> nil #TODO: return error
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
      # _ -> nil #TODO: return error
    end
  end

  defp parse_date(value) do
    if(value !== nil) do
      #the -2 is to account for an Excel bug (search in internet)
      Date.add(~D[1900-01-01], value - 2)
    else
      nil
    end
  end

  defp parse_comma_delimited(value) do
    if(value !== nil) do
      value
      |> String.split(",")
      |> Enum.map(&String.trim(&1))
      |> Enum.filter(&(String.length(&1) > 0))
    else
      []
    end
  end
end
