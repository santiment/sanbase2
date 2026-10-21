defmodule Sanbase.Billing.BusinessClients.Usage do
  @moduledoc ~s"""
  Usage signals shown next to each business client: API calls made with an API key
  and the last web session activity.

  Display only - nothing here feeds a metric. Every function answers for all the given
  users in one query and returns `%{}` when the query fails, so a slow or unreachable
  ClickHouse never takes the page down.
  """

  require Logger

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Repo

  @doc ~s"""
  API key calls per user in `[from, to)`, as a map of user id to count. Users without
  calls are absent.
  """
  @spec api_calls_per_user([integer()], DateTime.t(), DateTime.t()) ::
          %{integer() => non_neg_integer()}
  def api_calls_per_user([], _from, _to), do: %{}

  def api_calls_per_user(user_ids, from, to) do
    sql = """
    SELECT user_id, toUInt64(count())
    FROM api_call_data
    WHERE dt >= toDateTime({{from}}) AND dt < toDateTime({{to}})
      AND auth_method = 'apikey' AND user_id IN ({{user_ids}})
    GROUP BY user_id
    """

    Sanbase.Clickhouse.Query.new(sql, %{from: from, to: to, user_ids: user_ids})
    |> ClickhouseRepo.query_reduce(%{}, fn [user_id, count], acc ->
      Map.put(acc, user_id, count)
    end)
    |> ok_or_empty("api_calls_per_user")
  end

  @doc ~s"""
  API key calls per user in the `days` before `until` and in the `days` before that,
  in a single query. Returns `%{user_id => {current, previous}}`; users without calls
  in either window are absent.
  """
  @spec api_calls_two_windows([integer()], pos_integer(), DateTime.t()) ::
          %{integer() => {non_neg_integer(), non_neg_integer()}}
  def api_calls_two_windows([], _days, _until), do: %{}

  def api_calls_two_windows(user_ids, days, until) do
    middle = DateTime.add(until, -days, :day)
    from = DateTime.add(middle, -days, :day)

    sql = """
    SELECT
      user_id,
      toUInt64(countIf(dt >= toDateTime({{middle}}))),
      toUInt64(countIf(dt < toDateTime({{middle}})))
    FROM api_call_data
    WHERE dt >= toDateTime({{from}}) AND dt < toDateTime({{until}})
      AND auth_method = 'apikey' AND user_id IN ({{user_ids}})
    GROUP BY user_id
    """

    params = %{from: from, middle: middle, until: until, user_ids: user_ids}

    Sanbase.Clickhouse.Query.new(sql, params)
    |> ClickhouseRepo.query_reduce(%{}, fn [user_id, current, previous], acc ->
      Map.put(acc, user_id, {current, previous})
    end)
    |> ok_or_empty("api_calls_two_windows")
  end

  @doc ~s"""
  The last web or app session activity per user, from the refresh tokens in
  `guardian_tokens`: the latest of `last_exchanged_at` and `updated_at`, as in
  `SanbaseWeb.Guardian.Token.user_id_last_activity/1`. API key traffic does not
  show here.
  """
  @spec last_web_activity([integer()]) :: %{integer() => DateTime.t()}
  def last_web_activity([]), do: %{}

  def last_web_activity(user_ids) do
    sql = """
    SELECT sub::bigint AS user_id, MAX(GREATEST(last_exchanged_at, updated_at))
    FROM guardian_tokens
    WHERE sub = ANY($1::text[])
    GROUP BY sub
    """

    case Repo.query(sql, [Enum.map(user_ids, &to_string/1)]) do
      {:ok, %{rows: rows}} ->
        Map.new(rows, fn [user_id, datetime] -> {user_id, to_datetime(datetime)} end)

      {:error, error} ->
        ok_or_empty({:error, error}, "last_web_activity")
    end
  rescue
    error -> ok_or_empty({:error, error}, "last_web_activity")
  end

  defp to_datetime(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")
  defp to_datetime(datetime), do: datetime

  defp ok_or_empty({:ok, result}, _name), do: result

  defp ok_or_empty({:error, error}, name) do
    Logger.warning("[BusinessClients.Usage] #{name} failed: #{inspect(error)}")
    %{}
  end
end
