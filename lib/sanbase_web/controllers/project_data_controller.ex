defmodule SanbaseWeb.ProjectDataController do
  use SanbaseWeb, :controller

  alias Sanbase.Model.Project
  require Logger

  def data(conn, _params) do
    cache_key = {__MODULE__, __ENV__.function} |> Sanbase.Cache.hash()
    {:ok, data} = Sanbase.Cache.get_or_store(cache_key, &get_data/0)

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.send_resp(200, data)
  end

  defp get_data() do
    data =
      Project.List.projects(
        preload?: true,
        preload: [:infrastructure, :github_organizations, :contract_addresses]
      )
      |> Enum.map(fn project ->
        infr_code =
          case project do
            %{infrastructure: %{code: infr_code}} -> infr_code || ""
            _ -> ""
          end

        {:ok, github_organizations} = Project.github_organizations(project)

        {contract, decimals} =
          case Project.contract_info(project) do
            {:ok, contract, decimals} -> {contract, decimals}
            _ -> {"", 0}
          end

        project_json =
          %{
            slug: project.slug,
            ticker: project.ticker,
            infrastructure: infr_code,
            github_organizations: github_organizations |> Enum.join(","),
            contract: contract,
            decimals: decimals
          }
          |> Jason.encode!()

        [project_json, "\n"]
      end)

    {:ok, data}
  end
end
