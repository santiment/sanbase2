defmodule Sanbase.Graphql.ProjectApiEthContractTest do
  use SanbaseWeb.ConnCase, async: false

  require Sanbase.Utils.Config

  alias Sanbase.Model.Project
  alias Sanbase.Model.Ico
  alias Sanbase.Repo
  alias Sanbase.Utils.Config

  import Plug.Conn
  import SanbaseWeb.Graphql.TestHelpers

  test "fetch wallet projects with ethereum contract info", context do
    project1 =
      %Project{}
      |> Project.changeset(%{
        name: "Project1",
        ticker: "P1",
        coinmarketcap_id: "P1_id",
        main_contract_address: "address"
      })
      |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{
      project_id: project1.id,
      start_date: "2017-01-01",
      contract_block_number: 1234,
      contract_abi: "contract_abi1"
    })
    |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{
      project_id: project1.id,
      start_date: "2018-01-01",
      contract_block_number: 1_234_444,
      contract_abi: "contract_abi111"
    })
    |> Repo.insert!()

    project2 =
      %Project{}
      |> Project.changeset(%{name: "Project2", ticker: "P2", coinmarketcap_id: "P2_id"})
      |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{project_id: project2.id, start_date: "2017-01-01"})
    |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{
      project_id: project2.id,
      start_date: "2018-01-01",
      contract_block_number: 5678,
      contract_abi: "contract_abi22"
    })
    |> Repo.insert!()

    query = """
    {
      allProjectsWithEthContractInfo {
        name,
        ticker,
        initialIco {
          contractBlockNumber,
          contractAbi
        }
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", get_authorization_header())
      |> post("/graphql", query_skeleton(query, "allProjects"))

    assert json_response(result, 200)["data"]["allProjectsWithEthContractInfo"] ==
             [
               %{
                 "name" => "Project1",
                 "ticker" => "P1",
                 "initialIco" => %{
                   "contractBlockNumber" => 1234,
                   "contractAbi" => "contract_abi1"
                 }
               }
             ]
  end

  defp get_authorization_header do
    username = context_config(:basic_auth_username)
    password = context_config(:basic_auth_password)

    "Basic " <> Base.encode64(username <> ":" <> password)
  end

  defp context_config(key) do
    Config.module_get(SanbaseWeb.Graphql.ContextPlug, key)
  end
end
