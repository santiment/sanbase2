defmodule Sanbase.Graphql.ProjectApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  require Sanbase.Utils.Config

  alias Sanbase.Model.Project
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency
  alias Sanbase.Model.IcoCurrencies
  alias Sanbase.Model.ProjectEthAddress
  alias Sanbase.Model.LatestEthWalletData
  alias Sanbase.Repo
  alias Sanbase.Utils.Config

  import Plug.Conn

  defp query_skeleton(query, query_name, variable_defs \\"", variables \\ "{}") do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name}#{variable_defs} #{query}",
      "variables" => "#{variables}"
    }
  end

  test "fetch wallet balance for project transparency", context do
    project1 = %Project{}
    |> Project.changeset(%{name: "Project1", project_transparency: true})
    |> Repo.insert!

    %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{project_id: project1.id, address: "abcdefg", project_transparency: true})
    |> Repo.insert!

    %LatestEthWalletData{}
    |> LatestEthWalletData.changeset(%{address: "abcdefg", update_time: Ecto.DateTime.utc(), balance: 500})
    |> Repo.insert!

    %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{project_id: project1.id, address: "rrrrr"})
    |> Repo.insert!

    %LatestEthWalletData{}
    |> LatestEthWalletData.changeset(%{address: "rrrrr", update_time: Ecto.DateTime.utc(), balance: 800})
    |> Repo.insert!

    query = """
    {
      project(id:$id, onlyProjectTransparency:true) {
        name,
        btcBalance,
        ethBalance
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", get_authorization_header())
      |> post("/graphql", query_skeleton(query, "project", "($id:ID!)", "{\"id\": #{project1.id}}"))

    assert json_response(result, 200)["data"]["project"] == %{"name" => "Project1", "btcBalance" => nil, "ethBalance" => "500"}
  end

  test "fetch funds raised from icos", context do
    currency_eth = %Currency{}
    |> Currency.changeset(%{code: "ETH"})
    |> Repo.insert!

    currency_btc = %Currency{}
    |> Currency.changeset(%{code: "BTC"})
    |> Repo.insert!

    currency_usd = %Currency{}
    |> Currency.changeset(%{code: "USD"})
    |> Repo.insert!

    project1 = %Project{}
    |> Project.changeset(%{name: "Project1"})
    |> Repo.insert!

    ico1_1 = %Ico{}
    |> Ico.changeset(%{project_id: project1.id})
    |> Repo.insert!

    %IcoCurrencies{}
    |> IcoCurrencies.changeset(%{ico_id: ico1_1.id, currency_id: currency_usd.id, amount: 123.45})
    |> Repo.insert!

    project2 = %Project{}
    |> Project.changeset(%{name: "Project2"})
    |> Repo.insert!

    ico2_1 = %Ico{}
    |> Ico.changeset(%{project_id: project2.id})
    |> Repo.insert!

    %IcoCurrencies{}
    |> IcoCurrencies.changeset(%{ico_id: ico2_1.id, currency_id: currency_usd.id, amount: 100})
    |> Repo.insert!

    %IcoCurrencies{}
    |> IcoCurrencies.changeset(%{ico_id: ico2_1.id, currency_id: currency_eth.id, amount: 50})
    |> Repo.insert!

    %IcoCurrencies{}
    |> IcoCurrencies.changeset(%{ico_id: ico2_1.id, currency_id: currency_btc.id, amount: 300})
    |> Repo.insert!

    ico2_2 = %Ico{}
    |> Ico.changeset(%{project_id: project2.id})
    |> Repo.insert!

    %IcoCurrencies{}
    |> IcoCurrencies.changeset(%{ico_id: ico2_2.id, currency_id: currency_usd.id, amount: 200})
    |> Repo.insert!

    query = """
    {
      project(id:$id, onlyProjectTransparency:true) {
        name,
        fundsRaisedIcos {
          amount,
          currencyCode
        }
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", get_authorization_header())
      |> post("/graphql", query_skeleton(query, "project", "($id:ID!)", "{\"id\": #{project1.id}}"))

    assert json_response(result, 200)["data"]["project"] ==
      %{"name" => "Project1", "fundsRaisedIcos" =>
        [%{"currencyCode" => "USD", "amount" => "123.45"}]}

    result =
      context.conn
      |> put_req_header("authorization", get_authorization_header())
      |> post("/graphql", query_skeleton(query, "project", "($id:ID!)", "{\"id\": #{project2.id}}"))

      assert json_response(result, 200)["data"]["project"] ==
        %{"name" => "Project2", "fundsRaisedIcos" =>
          [%{"currencyCode" => "BTC", "amount" => "300"},
            %{"currencyCode" => "ETH", "amount" => "50"},
            %{"currencyCode" => "USD", "amount" => "300"}]}
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
