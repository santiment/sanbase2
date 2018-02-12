defmodule Sanbase.Etherbi.Utils do
  @moduledoc ~S"""
    If the difference between the datetimes is too large the query will be too big
    Allow the max difference between the datetimes to be 1 month by default. You can
    override this by passing a third parameter in seconds
  """

  import Ecto.Query

  @doc ~S"""
    Returns a list of all tickers that are used in etherbi
  """
  @spec get_tickers() :: list(binary())
  def get_tickers() do
    projects = Sanbase.Model.Project.all_projects_with_eth_contract_query()
    query = from(p in subquery(projects), where: not is_nil(p.token_decimals), select: p.ticker)
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
  """
  def generate_from_to_interval_unix(nil), do: nil

  def generate_from_to_interval_unix(from_datetime) do
    to_datetime = calculate_to_datetime(from_datetime, DateTime.utc_now())

    {from_datetime, to_datetime}
  end

  defp calculate_to_datetime(from_datetime, to_datetime, limit_sec \\ 60 * 60 * 24 * 30) do
    if DateTime.diff(to_datetime, from_datetime, :seconds) > limit_sec do
      Sanbase.DateTimeUtils.seconds_after(limit_sec, from_datetime)
    else
      to_datetime
    end
  end
end
