defmodule SanbaseWeb.Graphql.DynamicUserListTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Auth.User
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user =
      %User{
        salt: User.generate_salt(),
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    stablecoin = insert(:market_segment, %{name: "stablecoin"})
    coin = insert(:market_segment, %{name: "coin"})
    mineable = insert(:market_segment, %{name: "mineable"})

    insert(:project, %{ticker: "TUSD", coinmarketcap_id: "tether", market_segment: stablecoin})
    insert(:project, %{ticker: "DAI", coinmarketcap_id: "dai", market_segment: stablecoin})

    insert(:project, %{ticker: "ETH", coinmarketcap_id: "ethereum", market_segment: mineable})
    insert(:project, %{ticker: "BTC", coinmarketcap_id: "bitcoin", market_segment: mineable})
    insert(:project, %{ticker: "XRP", coinmarketcap_id: "ripple", market_segment: mineable})

    insert(:project, %{ticker: "BNB", coinmarketcap_id: "binance-coin", market_segment: coin})
    insert(:project, %{ticker: "SAN", coinmarketcap_id: "santiment", market_segment: coin})

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "create user list", %{user: user, conn: conn} do
    function =
      %{"name" => "market_segment", "args" => %{"market_segment" => "stablecoin"}}
      |> Jason.encode!()

    query =
      ~s|
    mutation {
      createUserList(
        name: 'My list'
        color: BLACK
        function: '#{function}'
        ) {
         id
         name
         color
         isPublic
         user{ id }

         listItems{
           project{ slug }
         }
      }
    }
    |
      |> String.replace(~r|\"|, ~S|\\"|)
      |> String.replace(~r|'|, ~S|"|)

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))
      |> json_response(200)

    user_list = result["data"]["createUserList"]

    assert user_list["name"] == "My list"
    assert user_list["color"] == "BLACK"
    assert user_list["isPublic"] == false
    assert user_list["user"]["id"] == user.id |> to_string()

    assert user_list["listItems"] == [
             %{"project" => %{"slug" => "dai"}},
             %{"project" => %{"slug" => "tether"}}
           ]
  end
end
