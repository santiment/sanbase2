defmodule SanbaseWeb.Graphql.UserEthAccountApiTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Auth.User
  alias Sanbase.Repo

  import Tesla.Mock
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  @address "0x12131415"
  @address2 "0x5432100"
  setup do
    user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "add eth account", context do
    result = add_eth_address(context.conn, @address)

    assert result == %{
             "data" => %{
               "addUserEthAddress" => %{"ethAccounts" => [%{"address" => @address}]}
             }
           }
  end

  test "add 2 eth accounts", context do
    add_eth_address(context.conn, @address)
    result = add_eth_address(context.conn, @address2)

    assert result == %{
             "data" => %{
               "addUserEthAddress" => %{
                 "ethAccounts" => [%{"address" => @address}, %{"address" => @address2}]
               }
             }
           }
  end

  test "cannot remove eth account if there is no email or another eth account set", context do
    add_eth_address(context.conn, @address)

    assert capture_log(fn ->
             result = remove_eth_address(context.conn, @address)
             %{"errors" => [error]} = result
             assert error["message"] == "Could not remove an ethereum address."
           end) =~ "There must be an email or other ethereum address set."
  end

  test "can remove eth account if there is another account set", context do
    add_eth_address(context.conn, @address)
    add_eth_address(context.conn, @address2)
    result = remove_eth_address(context.conn, @address)

    assert result == %{
             "data" => %{
               "removeUserEthAddress" => %{
                 "ethAccounts" => [%{"address" => @address2}]
               }
             }
           }
  end

  test "can remove eth account if there is email set", context do
    User.changeset(context.user, %{email: "somerandomemail@santiment.net"}) |> Repo.update()
    add_eth_address(context.conn, @address)
    result = remove_eth_address(context.conn, @address)

    assert result == %{
             "data" => %{
               "removeUserEthAddress" => %{
                 "ethAccounts" => []
               }
             }
           }
  end

  test "cannot have duplicated eth addresses", context do
    add_eth_address(context.conn, @address)

    assert capture_log(fn ->
             result = add_eth_address(context.conn, @address)
             %{"errors" => [error]} = result
             assert error["message"] == "Could not add an ethereum address."
           end) =~ ~s/[address: {"has already been taken", []}]/
  end

  # Helper functions

  defp add_eth_address(conn, address) do
    mock(fn %{method: :get} ->
      {:ok, %Tesla.Env{status: 200, body: %{"recovered" => address} |> Jason.encode!()}}
    end)

    mutation = """
    mutation {
      addUserEthAddress(address: "#{address}", signature: "fake", messageHash: "fake"){
        ethAccounts{
          address
        }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp remove_eth_address(conn, address) do
    mutation = """
    mutation {
      removeUserEthAddress(address: "#{address}"){
        ethAccounts{
          address
        }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
