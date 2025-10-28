defmodule SanbaseWeb.InactiveUsersController do
  @moduledoc """
  Controller for the inactive users CSV export.

  Re-runs the search query based on provided parameters and generates
  the CSV on the fly, avoiding URL length limits and data exposure in logs.
  """

  use SanbaseWeb, :controller

  alias Sanbase.Accounts.UserStats

  def download_csv(conn, params) do
    inactive_days = parse_integer(params["inactive_days"], 14)
    prior_activity_days = parse_integer(params["prior_activity_days"], 30)
    require_prior_activity = parse_boolean(params["require_prior_activity"], true)

    case UserStats.inactive_users_with_activity(
           inactive_days,
           prior_activity_days,
           require_prior_activity
         ) do
      {:ok, users} ->
        csv_content = generate_csv(users)

        conn
        |> put_resp_content_type("text/csv; charset=utf-8")
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"inactive_users_#{DateTime.utc_now() |> DateTime.to_date()}.csv\""
        )
        |> send_resp(200, csv_content)

      {:error, reason} ->
        conn
        |> put_status(400)
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "Failed to fetch users: #{reason}")
    end
  end

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> num
      :error -> default
    end
  end

  defp parse_integer(nil, default), do: default

  defp parse_boolean(value, default) when is_binary(value) do
    case value do
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  defp parse_boolean(nil, default), do: default

  defp generate_csv(users) do
    ["email,name"]
    |> Enum.concat(
      Enum.map(users, fn user ->
        "#{user.email || ""},#{user.name || ""}"
      end)
    )
    |> Enum.join("\n")
  end
end
