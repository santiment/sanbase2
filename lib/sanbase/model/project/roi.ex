defmodule Sanbase.Model.Project.Roi do
  alias Sanbase.Repo
  alias Sanbase.Model.{Project, Ico}

  @doc ~S"""
  ROI = current_price*(ico1_tokens + ico2_tokens + ...)/(ico1_tokens*ico1_initial_price + ico2_tokens*ico2_initial_price + ...)
  We skip ICOs for which we can't calculate the initial_price or the tokens sold
  For ICOs that we don't have tokens sold we try to fill it heuristically by evenly distributing the rest of the total available supply
  """
  def roi_usd(%Project{ticker: ticker, coinmarketcap_id: coinmarketcap_id} = project)
      when not is_nil(ticker) and not is_nil(coinmarketcap_id) do
    with %Project{} = project <- Repo.preload(project, [:latest_coinmarketcap_data, :icos]),
         false <- is_nil(project.latest_coinmarketcap_data),
         false <- is_nil(project.latest_coinmarketcap_data.price_usd),
         false <- is_nil(project.latest_coinmarketcap_data.available_supply) do
      zero = Decimal.new(0)

      tokens_and_initial_prices =
        project
        |> fill_missing_tokens_sold_at_icos()
        |> Enum.map(fn ico ->
          {ico.tokens_sold_at_ico, calc_token_usd_ico_price_by_project(project, ico)}
        end)
        |> Enum.reject(fn {tokens_sold_at_ico, token_usd_ico_price} ->
          is_nil(tokens_sold_at_ico) or is_nil(token_usd_ico_price)
        end)

      total_cost =
        tokens_and_initial_prices
        |> Enum.map(fn {tokens_sold_at_ico, token_usd_ico_price} ->
          Decimal.mult(tokens_sold_at_ico, token_usd_ico_price)
        end)
        |> Enum.reduce(zero, &Decimal.add/2)

      total_gain =
        tokens_and_initial_prices
        |> Enum.map(fn {tokens_sold_at_ico, _} -> tokens_sold_at_ico end)
        |> Enum.reduce(zero, &Decimal.add/2)
        |> Decimal.mult(project.latest_coinmarketcap_data.price_usd)

      case total_cost do
        ^zero -> nil
        total_cost -> Decimal.div(total_gain, total_cost)
      end
    else
      _ -> nil
    end
  end

  def roi_usd(_), do: nil

  # Private functions

  # Heuristic: fills empty ico.tokens_sold_at_ico by evenly distributing the rest of the circulating supply
  # TODO:
  # Currently uses latest_coinmarketcap_data.available_supply, which also includes coins not issued at any ICO
  # Maybe it's better to keep historical data of available_supply so that we can calculate it better
  defp fill_missing_tokens_sold_at_icos(%Project{} = project) do
    with tokens_sold_at_icos <- Enum.map(project.icos, & &1.tokens_sold_at_ico),
         unknown_count <- Enum.filter(tokens_sold_at_icos, &is_nil/1) |> length(),
         true <- unknown_count > 0 do
      zero = Decimal.new(0)
      one = Decimal.new(1)

      known_tokens_sum =
        tokens_sold_at_icos
        |> Enum.reject(&is_nil/1)
        |> Enum.reduce(zero, &Decimal.add/2)

      unknown_tokens_sum =
        Decimal.compare(project.latest_coinmarketcap_data.available_supply, known_tokens_sum)
        |> case do
          ^one ->
            Decimal.sub(project.latest_coinmarketcap_data.available_supply, known_tokens_sum)

          _ ->
            zero
        end

      unknown_tokens_single_ico = Decimal.div(unknown_tokens_sum, Decimal.new(unknown_count))

      Enum.map(project.icos, fn ico ->
        if is_nil(ico.tokens_sold_at_ico) do
          Map.put(ico, :tokens_sold_at_ico, unknown_tokens_single_ico)
        else
          ico
        end
      end)
    else
      _ -> project.icos
    end
  end

  defp calc_token_usd_ico_price_by_project(%Project{} = project, %Ico{} = ico) do
    ico.token_usd_ico_price ||
      calc_token_usd_ico_price(
        ico.token_eth_ico_price,
        "ETH",
        ico.start_date,
        project.latest_coinmarketcap_data.update_time
      ) ||
      calc_token_usd_ico_price(
        ico.token_btc_ico_price,
        "BTC",
        ico.start_date,
        project.latest_coinmarketcap_data.update_time
      )
  end

  defp calc_token_usd_ico_price(nil, _currency_from, _ico_start_date, _current_datetime), do: nil
  defp calc_token_usd_ico_price(_price_from, _currency_from, nil, _current_datetime), do: nil

  defp calc_token_usd_ico_price(price_from, currency_from, ico_start_date, current_datetime) do
    with :gt <- Ecto.DateTime.compare(current_datetime, Ecto.DateTime.from_date(ico_start_date)),
         timestamp <- Sanbase.DateTimeUtils.ecto_date_to_datetime(ico_start_date),
         price_usd when not is_nil(price_usd) <-
           Sanbase.Prices.Utils.fetch_last_price_before(currency_from, "USD", timestamp) do
      Decimal.mult(price_from, Decimal.new(price_usd))
    else
      _ -> nil
    end
  end
end
