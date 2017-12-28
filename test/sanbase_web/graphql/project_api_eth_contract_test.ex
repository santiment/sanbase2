defmodule Sanbase.Graphql.ProjectApiEthContractTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  import Sanbase.Utils, only: [parse_config_value: 1]

  alias Ecto.Changeset
  alias Sanbase.Graphql.ProjectInfo
  alias Sanbase.Model.Project
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency
  alias Sanbase.Model.IcoCurrencies
  alias Sanbase.Model.ProjectEthAddress
  alias Sanbase.Model.LatestEthWalletData
  alias Sanbase.Repo

  import Plug.Conn
  import ExUnit.CaptureLog

  defp query_skeleton(query, query_name) do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name} #{query}",
      "variables" => "{}"
    }
  end

  test "fetch wallet projects with ethereum contract info", context do
    project1 = %Project{}
    |> Project.changeset(%{name: "Project1", project_transparency: true})
    |> Repo.insert!

    addr1_1 = %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{project_id: project1.id, address: "abcdefg", project_transparency: true})
    |> Repo.insert!

    addr1_1_data = %LatestEthWalletData{}
    |> LatestEthWalletData.changeset(%{address: "abcdefg", update_time: Ecto.DateTime.utc(), balance: 500})
    |> Repo.insert!

    addr1_2 = %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{project_id: project1.id, address: "rrrrr"})
    |> Repo.insert!

    addr1_2_data = %LatestEthWalletData{}
    |> LatestEthWalletData.changeset(%{address: "rrrrr", update_time: Ecto.DateTime.utc(), balance: 800})
    |> Repo.insert!

    query = """
    {
      allProjects(onlyProjectTransparency:true) {
        name,
        btcBalance,
        ethBalance
      }
    }
    """

    result =
    context.conn
    |> put_req_header("authorization", get_authorization_header())
    |> post("/graphql", query_skeleton(query, "allProjects"))

    assert json_response(result, 200)["data"]["allProjects"] == [%{"name" => "Project1", "btcBalance" => nil, "ethBalance" => "500"}]
  end

  test "fetch wallet projects with ethereum contract info", context do
    project1 = %Project{}
    |> Project.changeset(%{name: "Project1", ticker:"P1"})
    |> Repo.insert!

    ico1_1 = %Ico{}
    |> Ico.changeset(
      %{project_id: project1.id,
        start_date: Ecto.Date.cast("2017-01-01"),
        main_contract_address: "main_contract_address1",
        contract_block_number: 1234,
        contract_abi: "contract_abi1"
        })
    |> Repo.insert!

    ico1_2 = %Ico{}
    |> Ico.changeset(
      %{project_id: project1.id,
        start_date: Ecto.Date.cast("2018-01-01"),
        main_contract_address: "main_contract_address111",
        contract_block_number: 1234444,
        contract_abi: "contract_abi111"
        })
    |> Repo.insert!

    project2 = %Project{}
    |> Project.changeset(%{name: "Project2", ticker:"P2"})
    |> Repo.insert!

    ico2_1 = %Ico{}
    |> Ico.changeset(
      %{project_id: project2.id,
        start_date: Ecto.Date.cast("2017-01-01")
        })
    |> Repo.insert!

    ico2_1 = %Ico{}
    |> Ico.changeset(
      %{project_id: project2.id,
        start_date: Ecto.Date.cast("2018-01-01"),
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

    main_contract_address: "main_contract_address1",
    contract_block_number: 1234,
    contract_abi: "contract_abi1"

    result =
    context.conn
    |> put_req_header("authorization", get_authorization_header())
    |> post("/graphql", query_skeleton(query, "allProjects"))

    assert json_response(result, 200)["data"]["allProjectsWithEthContractInfo"] ==
      [%{"name" => "Project1", "ticker" => "P1", "initialIco" =>
        [%{"mainContractAddress" => "main_contract_address1"
        , "contractBlockNumber" => "1234"
        , "contractAbi" => "contract_abi1"}]}]
  end

  defp get_authorization_header do
    username = context_config(:basic_auth_username)
    password = context_config(:basic_auth_password)

    "Basic " <> Base.encode64(username <> ":" <> password)
  end

  defp context_config(key) do
    Application.get_env(:sanbase, SanbaseWeb.Graphql.ContextPlug)
    |> Keyword.get(key)
    |> parse_config_value()
  end
end
