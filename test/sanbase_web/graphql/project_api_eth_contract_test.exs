defmodule Sanbase.Graphql.ProjectApiEthContractTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  require Sanbase.Utils.Config

  alias Ecto.Changeset
  alias Sanbase.Graphql.ProjectInfo
  alias Sanbase.Model.Project
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency
  alias Sanbase.Model.IcoCurrencies
  alias Sanbase.Model.ProjectEthAddress
  alias Sanbase.Model.LatestEthWalletData
  alias Sanbase.Repo
  alias Sanbase.Utils.Config

  import Plug.Conn
  import ExUnit.CaptureLog

  defp query_skeleton(query, query_name, variables \\ "{}") do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name} #{query}",
      "variables" => "#{variables}"
    }
  end

  test "fetch wallet projects with ethereum contract info", context do
    project1 = %Project{}
    |> Project.changeset(%{name: "Project1", ticker: "P1", coinmarketcap_id: "P1_id"})
    |> Repo.insert!

    ico1_1 = %Ico{}
    |> Ico.changeset(
      %{project_id: project1.id,
        start_date: "2017-01-01",
        main_contract_address: "main_contract_address1",
        contract_block_number: 1234,
        contract_abi: "contract_abi1"
        })
    |> Repo.insert!

    ico1_2 = %Ico{}
    |> Ico.changeset(
      %{project_id: project1.id,
        start_date: "2018-01-01",
        main_contract_address: "main_contract_address111",
        contract_block_number: 1234444,
        contract_abi: "contract_abi111"
        })
    |> Repo.insert!

    project2 = %Project{}
    |> Project.changeset(%{name: "Project2", ticker: "P2", coinmarketcap_id: "P2_id"})
    |> Repo.insert!

    ico2_1 = %Ico{}
    |> Ico.changeset(
      %{project_id: project2.id,
        start_date: "2017-01-01"
        })
    |> Repo.insert!

    ico2_1 = %Ico{}
    |> Ico.changeset(
      %{project_id: project2.id,
        start_date: "2018-01-01",
        main_contract_address: "main_contract_address2222",
        contract_block_number: 5678,
        contract_abi: "contract_abi22"
        })
    |> Repo.insert!

    query = """
    {
      allProjectsWithEthContractInfo {
        name,
        ticker,
        initialIco {
          mainContractAddress,
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
      [%{"name" => "Project1", "ticker" => "P1", "initialIco" =>
        %{"mainContractAddress" => "main_contract_address1",
        "contractBlockNumber" => 1234,
        "contractAbi" => "contract_abi1"}}]
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
