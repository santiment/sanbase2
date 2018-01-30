defmodule Sanbase.Etherbi.Utils do
  @doc ~S"""
    If the difference between the datetimes is too large the query will be too big
    Allow the max difference between the datetimes to be 1 month by default. You can
    override this by passing a third parameter in seconds
  """

  import Ecto.Query

  @spec calculate_to_datetime(%DateTime{}, %DateTime{}) :: %DateTime{}
  def calculate_to_datetime(from_datetime, to_datetime, limit_sec \\ 60 * 60 * 24) do
    if DateTime.diff(to_datetime, from_datetime, :seconds) > limit_sec do
      Sanbase.DateTimeUtils.seconds_after(limit_sec, from_datetime)
    else
      to_datetime
    end
  end

  @doc ~S"""
    Returns a list of all tickers that are used in etherbi
  """
  @spec get_tickers() :: list(binary())
  def get_tickers() do
    projects = Sanbase.Model.Project.all_projects_with_eth_contract_query()
    query = from(p in subquery(projects), select: p.ticker)
    Sanbase.Repo.all(query)
  end

  @doc ~s"""
    Build a map that contains tickers as keys and :math.pow(10, decimal_places) as value
  """
  @spec build_token_decimals_map() :: map()
  def build_token_decimals_map() do
    query =
      from(
        p in Sanbase.Model.Project,
        where: not is_nil(p.token_decimals),
        select: %{ticker: p.ticker, token_decimals: p.token_decimals}
      )

    Sanbase.Repo.all(query)
    |> Enum.map(fn %{ticker: ticker, token_decimals: token_decimals} ->
      {ticker, :math.pow(10, token_decimals)}
    end)
    |> Map.new()
  end

  @doc ~S"""
    Get a tuple `{from, to}` to use in a query or `nil` if there is no info.
    If there is no record in the DB for that address and Etherbi's
    first transaction volume timestamp API returns no result then there are no transactions
    In that case return `nil` and detect in the caller that no query should be made
  """
  def generate_from_to_interval_unix(
        ticker,
        [
          db_last_datetime: last_datetime_func,
          etherbi_first_timestamp: first_timestamp_func
        ]
      ) do
    # Returns {:ok, nil} if there are no records for that measurement
    {:ok, from_datetime} = last_datetime_func.(ticker)

    from_datetime =
      if from_datetime do
        from_datetime
      else
        # {:ok, from_datetime} = @etherbi_api.get_first_burn_rate_timestamp(ticker)
        {:ok, from_datetime} = first_timestamp_func.(ticker)
        from_datetime
      end

    if from_datetime do
      to_datetime = calculate_to_datetime(from_datetime, DateTime.utc_now())

      {from_datetime, to_datetime}
    else
      nil
    end
  end
end