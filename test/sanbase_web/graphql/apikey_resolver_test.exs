defmodule SanbaseWeb.Graphql.ApikeyResolverTest do
  use SanbaseWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers
  import Mockery

  alias Sanbase.Repo

  alias Sanbase.Auth.{
    User,
    UserApikeyToken,
    Hmac
  }

  setup do
    user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    user2 =
      %User{
        salt: User.generate_salt(),
        privacy_policy_accepted: true,
        test_san_balance: Decimal.new(2000)
      }
      |> Repo.insert!()

    conn2 = setup_jwt_auth(build_conn(), user2)

    %{conn: conn, conn2: conn2, user: user, user2: user2}
  end

  test "generate a valid apikey", %{conn: conn} do
    apikeys =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    # A single apikey should be generated
    assert Enum.count(apikeys) == 1
    apikey = List.first(apikeys)

    # The generated apikey is valid
    assert apikey_valid?(apikey)
  end

  test "revoke an apikey", %{conn: conn} do
    # Generate and check that a valid single apikey is present
    apikeys =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    assert Enum.count(apikeys) == 1
    apikey = List.first(apikeys)
    assert apikey_valid?(apikey)

    # Revoke and check that the apikey is now not present and not valid
    apikeys2 =
      revoke_apikey(conn, apikey)
      |> json_response(200)
      |> extract_api_key_list()

    # There are no more apikeys
    assert apikeys2 == []

    # The previously valid apikey is now invalid
    refute apikey_valid?(apikey)
  end

  test "other users cannot revoke my apikey", %{conn: conn, conn2: conn2} do
    # Get apikey for user1
    apikey =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()
      |> List.first()

    # Check that user2 cannot revoke it
    result2 =
      revoke_apikey(conn2, apikey)
      |> json_response(200)

    err_struct = result2["errors"] |> List.first()
    assert err_struct["message"] =~ "Provided apikey is malformed or not valid"
  end

  test "can have more than one apikey", %{conn: conn} do
    generate_apikey(conn)
    generate_apikey(conn)

    [apikey1, apikey2, apikey3] =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    assert apikey_valid?(apikey1)
    assert apikey_valid?(apikey2)
    assert apikey_valid?(apikey3)
  end

  test "revoke apikey twice", %{conn: conn} do
    [apikey] =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    revoke_apikey(conn, apikey)
    revoke_apikey(conn, apikey)

    result =
      revoke_apikey(conn, apikey)
      |> json_response(200)

    err_struct = result["errors"] |> List.first()
    assert err_struct["message"] =~ "Provided apikey is malformed or not valid"
  end

  test "user dropped while the connection is up", %{conn: conn, user: user} do
    [apikey] =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    Repo.delete(user)

    assert capture_log(fn ->
             revoke_apikey(conn, apikey)
           end) =~ "[warn] Invalid bearer token in request"
  end

  test "on delete user delete all user's tokens", %{conn: conn, user: user} do
    generate_apikey(conn)

    [apikey1, apikey2] =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    Repo.delete(user)

    {:ok, {token1, _apikey}} = Hmac.split_apikey(apikey1)
    {:ok, {token2, _apikey}} = Hmac.split_apikey(apikey1)

    refute apikey_valid?(apikey1)
    refute apikey_valid?(apikey2)
    refute UserApikeyToken.has_token?(token1)
    refute UserApikeyToken.has_token?(token2)
  end

  test "cannot revoke malformed apikey", %{conn: conn} do
    [apikey] =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    apikey = apikey <> "s"

    result =
      revoke_apikey(conn, apikey)
      |> json_response(200)

    err_struct = result["errors"] |> List.first()
    assert err_struct["message"] =~ "Provided apikey is malformed or not valid"
  end

  describe "tests with apikey an API protected with MultipleAuth" do
    # user2 has 2000 test SAN balance
    test "access when user has enough tokens", %{conn2: conn2} do
      datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
      datetime2 = DateTime.from_naive!(~N[2017-05-13 21:55:00], "Etc/UTC")

      # Mock the queried api
      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: emojis_sentiment_body(datetime1, datetime2),
           status_code: 200
         }}
      )

      [apikey] =
        generate_apikey(conn2)
        |> json_response(200)
        |> extract_api_key_list()

      conn_apikey = setup_apikey_auth(build_conn(), apikey)
      query = emojis_sentiment_query(datetime1, datetime2)

      result =
        conn_apikey
        |> post("/graphql", query_skeleton(query, "emojisSentiment"))
        |> json_response(200)

      %{
        "data" => %{
          "emojisSentiment" => emojis_sentiment
        }
      } = result

      assert %{"sentiment" => 0} in emojis_sentiment
      assert %{"sentiment" => 1234} in emojis_sentiment
    end

    # conn's user has 0 SAN balance
    test "access refused when user does not have enough tokens",
         %{conn: conn} do
      datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
      datetime2 = DateTime.from_naive!(~N[2017-05-13 21:55:00], "Etc/UTC")

      # Mock the queried api
      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: emojis_sentiment_body(datetime1, datetime2),
           status_code: 200
         }}
      )

      [apikey] =
        generate_apikey(conn)
        |> json_response(200)
        |> extract_api_key_list()

      conn_apikey = setup_apikey_auth(build_conn(), apikey)
      query = emojis_sentiment_query(datetime1, datetime2)

      result =
        conn_apikey
        |> post("/graphql", query_skeleton(query, "emojisSentiment"))
        |> json_response(200)

      err_struct = result["errors"] |> List.first()
      assert err_struct["message"] =~ "unauthorized"
    end
  end

  test "access realtime data behind API delay san staking", %{conn2: conn2} do
    # Store some data recent data
    slug = "santiment"
    datetime1 = Timex.shift(Timex.now(), hours: -1)
    datetime2 = Timex.now()
    init_databases(slug, datetime1, datetime2)

    # Get an apikey and build API conn
    [apikey] =
      generate_apikey(conn2)
      |> json_response(200)
      |> extract_api_key_list()

    conn_apikey = setup_apikey_auth(build_conn(), apikey)

    query = burn_rate_query(slug, datetime1, datetime2)

    result =
      conn_apikey
      |> post("/graphql", query_skeleton(query, "burnRate"))
      |> json_response(200)

    %{
      "data" => %{
        "burnRate" => burn_rates
      }
    } = result

    assert length(burn_rates) > 0
  end

  # Private functions

  defp apikey_valid?(apikey) do
    {:ok, {token, _apikey}} = Hmac.split_apikey(apikey)
    Hmac.apikey_valid?(token, apikey)
  end

  defp generate_apikey(conn) do
    query = """
    mutation {
      generateApikey {
        apikeys
      }
    }
    """

    conn |> post("/graphql", mutation_skeleton(query))
  end

  defp extract_api_key_list(%{
         "data" => %{
           "generateApikey" => %{
             "apikeys" => apikeys
           }
         }
       }) do
    apikeys
  end

  defp extract_api_key_list(%{
         "data" => %{
           "revokeApikey" => %{
             "apikeys" => apikeys
           }
         }
       }) do
    apikeys
  end

  defp revoke_apikey(conn, apikey) do
    query = """
    mutation {
      revokeApikey(apikey: "#{apikey}") {
        apikeys
      }
    }
    """

    conn |> post("/graphql", mutation_skeleton(query))
  end

  defp emojis_sentiment_query(datetime1, datetime2) do
    """
    {
      emojisSentiment(
        from: "#{datetime1}",
        to: "#{datetime2}",
        interval:"1d"){
          sentiment
      }
    }
    """
  end

  defp emojis_sentiment_body(datetime1, datetime2) do
    "[{
        \"sentiment\": 0,
        \"timestamp\": #{DateTime.to_unix(datetime1)}
      },
      {
        \"sentiment\": 1234,
        \"timestamp\": #{DateTime.to_unix(datetime2)}
      }
    ]"
  end

  defp init_databases(slug, datetime1, datetime2) do
    alias Sanbase.Influxdb.Measurement
    alias Sanbase.Etherbi.BurnRate.Store
    alias Sanbase.Repo
    alias Sanbase.Model.Project

    contract_address = "0x123123123"

    Store.import([
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{burn_rate: 5000},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{burn_rate: 1000},
        tags: [],
        name: contract_address
      }
    ])

    %Project{
      name: "Santiment",
      ticker: "SAN",
      coinmarketcap_id: slug,
      main_contract_address: contract_address
    }
    |> Repo.insert!()
  end

  defp burn_rate_query(slug, datetime1, datetime2) do
    """
    {
      burnRate(
        slug: "#{slug}",
        from: "#{datetime1}",
        to: "#{datetime2}",
        interval: "30m") {
          burnRate
          datetime
      }
    }
    """
  end
end
