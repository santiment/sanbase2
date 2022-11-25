defmodule SanbaseWeb.DataController do
  use SanbaseWeb, :controller

  alias Sanbase.Project
  alias Sanbase.Project.SocialVolumeQuery
  require Logger

  # In order to access the data, the endpoint needs to know the secret.
  # The path is https://api.santiment.net/santiment_team_members/the_real_secret
  # This contains information about users, so it cannot be publicly freely available
  def santiment_team_members(conn, %{"secret" => secret}) do
    case santiment_team_members_secret() == secret do
      true ->
        {:ok, data} = get_santiment_team_members()

        conn
        |> put_resp_header("content-type", "application/json; charset=utf-8")
        |> Plug.Conn.send_resp(200, data)

      false ->
        conn
        |> send_resp(403, "Unauthorized")
        |> halt()
    end
  end

  def projects_data(conn, _params) do
    cache_key = {__MODULE__, __ENV__.function} |> Sanbase.Cache.hash()
    {:ok, data} = Sanbase.Cache.get_or_store(cache_key, &get_projects_data/0)

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.send_resp(200, data)
  end

  defp get_santiment_team_members() do
    email_to_discord_id_map = get_email_to_discord_id_map()

    data =
      Sanbase.Accounts.Statistics.santiment_team_users()
      |> Enum.map(fn user ->
        discord_id = Map.get(email_to_discord_id_map, user.email)

        user_json =
          %{
            id: user.id,
            email: user.email || "",
            username: user.username || "",
            discord_id: discord_id || ""
          }
          |> Jason.encode!()

        [user_json, "\n"]
      end)

    {:ok, data}
  end

  defp get_projects_data() do
    data =
      Project.List.projects(
        preload?: true,
        preload: [
          :infrastructure,
          :github_organizations,
          :contract_addresses,
          :social_volume_query,
          :latest_coinmarketcap_data
        ]
      )
      |> Enum.map(fn project ->
        {:ok, github_organizations} = Project.github_organizations(project)
        infrastructure_code = project_to_infrastructure_code(project)
        {contract, decimals} = project_to_contract_decimals(project)
        rank = project_to_rank(project)
        social_volume_query = project_to_social_volume_query(project)

        project_json =
          %{
            slug: project.slug,
            ticker: project.ticker,
            name: project.name,
            infrastructure: infrastructure_code,
            github_organizations: github_organizations |> Enum.sort() |> Enum.join(","),
            contract: contract,
            decimals: decimals,
            social_volume_query: social_volume_query,
            rank: rank,
            telegram_chat_id: project.telegram_chat_id
          }
          |> Jason.encode!()

        [project_json, "\n"]
      end)

    {:ok, data}
  end

  defp project_to_infrastructure_code(project) do
    case project do
      %{infrastructure: %{code: infr_code}} -> infr_code || ""
      _ -> ""
    end
  end

  defp project_to_social_volume_query(project) do
    case project.social_volume_query do
      %SocialVolumeQuery{} = svq -> svq.query || svq.autogenerated_query
      nil -> ""
    end
  end

  defp project_to_rank(project) do
    case project.latest_coinmarketcap_data do
      %{} = lcd -> lcd.rank
      nil -> nil
    end
  end

  defp project_to_contract_decimals(project) do
    case Project.contract_info(project) do
      {:ok, contract, decimals} -> {contract, decimals}
      _ -> {"", 0}
    end
  end

  defp get_email_to_discord_id_map() do
    # Mounted as ConfigMap during deployment of the web pods
    path = "/mnt/santiment_team_members_discord_data.json"

    case File.read(path) do
      {:ok, content} ->
        content
        |> Jason.decode!()
        |> Map.new(fn %{"email" => email, "discord_id" => discord_id} ->
          {email, discord_id}
        end)

      _ ->
        %{}
    end
  end

  # On stage/prod the env var is set and is different from the default one.
  defp santiment_team_members_secret(),
    do:
      System.get_env("SANTIMENT_TEAM_MEMBERS_ENDPOINT_SECRET") ||
        "random_secret"
end
