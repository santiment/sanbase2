defmodule SanbaseWeb.DataController do
  use SanbaseWeb, :controller

  alias Sanbase.Project
  alias Sanbase.Project.SocialVolumeQuery
  require Logger

  @doc ~s"""
  In order to access the data, the caller needs to know the secret.
  The path is https://api.santiment.net/santiment_team_members/<the_real_secret>
  This contains information about santiment team users, so it cannot be publicly freely available
  """
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

  @doc ~s"""
  Return a list of data about the projects.
  This data is used to build the projects_data clickhouse dictionary.

  Each line of the response is a valid JSON object in the following format:
  {
    "decimals": 18,
    "name": "Ethereum",
    "ticker": "ETH",
    "rank": 2,
    "contract": "ETH",
    "slug": "ethereum",
    "infrastructure": "ETH",
    "telegram_chat_id": null,
    "github_organizations": "ethereum",
    "social_volume_query": "eth OR ether OR ethereum NOT cash NOT gold NOT classic"
  }
  """
  @spec projects_data(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def projects_data(conn, _params) do
    cache_key = {__MODULE__, __ENV__.function} |> Sanbase.Cache.hash()
    {:ok, data} = Sanbase.Cache.get_or_store(cache_key, &get_projects_data/0)

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.send_resp(200, data)
  end

  @doc ~s"""
  Return a list of data about the ecosystems.
  This data is used to build the ecosystems_data clickhouse dictionary.

  Each line of the response is a valid JSON object in the following format:

  {
    "ecosystem": "bitcoin",
    "asset_ids": [ 1482 ],
    "slugs": [ "bitcoin" ],
    "github_organizations": [ "bitcoin" ]
  }
  """
  @spec ecosystems_data(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ecosystems_data(conn, _params) do
    cache_key = {__MODULE__, __ENV__.function} |> Sanbase.Cache.hash()

    {:ok, ecosystems_data} = Sanbase.Cache.get_or_store(cache_key, &get_ecosystems_data/0)

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.send_resp(200, ecosystems_data)
  end

  # Private functions
  defp get_santiment_team_members() do
    email_to_discord_id_map = get_email_to_discord_id_map()

    data =
      Sanbase.Accounts.Statistics.santiment_team_users()
      |> Enum.map(fn user ->
        discord_id = Map.get(email_to_discord_id_map, user.email)

        %{
          id: user.id,
          email: user.email || "",
          username: user.username || "",
          discord_id: discord_id || ""
        }
        |> Jason.encode!()
      end)
      |> Enum.intersperse("\n")

    {:ok, data}
  end

  defp get_ecosystems_data() do
    with {:ok, slug_to_asset_id_map} <- get_slug_to_asset_id_map(),
         {:ok, data} <- Sanbase.Ecosystem.get_ecosystems_with_projects() do
      result =
        Enum.map(data, fn %{name: ecosystem, projects: projects} ->
          slugs = Enum.map(projects, & &1.slug)

          asset_ids =
            Enum.map(slugs, &Map.get(slug_to_asset_id_map, &1))
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          github_organizations =
            Enum.flat_map(projects, & &1.github_organizations)
            |> Enum.map(& &1.organization)
            |> Enum.uniq()

          %{
            ecosystem: ecosystem,
            slugs: slugs,
            asset_ids: asset_ids,
            github_organizations: github_organizations
          }
          |> Jason.encode!()
        end)
        |> Enum.intersperse("\n")

      {:ok, result}
    end
  end

  defp get_slug_to_asset_id_map() do
    query = "SELECT name AS slug, asset_id FROM asset_metadata FINAL"

    case Sanbase.ClickhouseRepo.query_transform(query, [], & &1) do
      {:ok, result} ->
        map = Map.new(result, fn [slug, asset_id] -> {slug, asset_id} end)

        {:ok, map}

      {:error, error} ->
        {:error, error}
    end
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
