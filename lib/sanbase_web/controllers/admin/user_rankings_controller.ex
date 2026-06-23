defmodule SanbaseWeb.Admin.UserRankingsController do
  @moduledoc """
  CSV export for the user-rankings admin page. Re-runs the cached ranking query
  with the given `rank_by`/`limit` and streams it as a CSV download.
  """

  use SanbaseWeb, :controller

  alias SanbaseWeb.Admin.UserRankings

  @headers ~w(rank user_id email username is_paid total_creations charts max_chart_metrics
              total_chart_metrics insights dashboards watchlists screeners max_watchlist_assets
              alerts queries addresses api_keys flags)

  def export(conn, params) do
    rank_by = Map.get(params, "rank_by", "total_creations")
    limit = Map.get(params, "limit", "200")

    case UserRankings.get(rank_by: rank_by, limit: limit) do
      {:ok, %{rows: rows}} ->
        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", ~s(attachment; filename="user_rankings.csv"))
        |> send_resp(200, build_csv(rows))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not build the rankings export.")
        |> redirect(to: ~p"/admin/user_rankings")
    end
  end

  defp build_csv(rows) do
    data =
      rows
      |> Enum.with_index(1)
      |> Enum.map(fn {row, idx} ->
        [
          idx,
          row.user_id,
          row.email,
          row.username,
          row.is_paid,
          row.total_creations,
          row.charts,
          row.max_chart_metrics,
          row.total_chart_metrics,
          row.insights,
          row.dashboards,
          row.watchlists,
          row.screeners,
          row.max_watchlist_assets,
          row.alerts,
          row.queries,
          row.addresses,
          row.api_keys,
          Enum.map_join(row.flags, "; ", fn {key, _reason} -> to_string(key) end)
        ]
        |> Enum.map(&cell/1)
      end)

    NimbleCSV.RFC4180.dump_to_iodata([@headers | data])
  end

  defp cell(nil), do: ""
  defp cell(value) when is_binary(value), do: value
  defp cell(value), do: to_string(value)
end
