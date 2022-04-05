defmodule Sanbase.TelegramTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Repo
  alias Sanbase.Accounts.{User, Settings, UserSettings}
  alias Sanbase.Telegram

  @bot_username Application.compile_env(:sanbase, [Sanbase.Telegram, :bot_username])
  @telegram_endpoint Application.compile_env(:sanbase, [Sanbase.Telegram, :telegram_endpoint])

  @telegram_chat_id 12_315

  setup do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "get telegram deep link", context do
    telegram_link = get_telegram_deep_link(context)

    %Telegram.UserToken{token: user_token} = Telegram.UserToken.by_user_id(context.user.id)

    assert telegram_link == "https://telegram.me/#{@bot_username}?start=#{user_token}"
  end

  test "process when user clicks start button in telegram", context do
    get_telegram_deep_link(context)

    %Telegram.UserToken{token: user_token} = Telegram.UserToken.by_user_id(context.user.id)

    # There are no settings before
    assert nil == UserSettings.settings_for(context.user, force: true).telegram_chat_id

    simulate_telegram_deep_link_follow(context, user_token)

    # Now there is a telegram chat id
    %Settings{telegram_chat_id: chat_id} = UserSettings.settings_for(context.user, force: true)
    assert chat_id == @telegram_chat_id
  end

  test "revoke telegram deep link removes the token", context do
    get_telegram_deep_link(context)

    %Telegram.UserToken{token: user_token} = Telegram.UserToken.by_user_id(context.user.id)
    assert String.length(user_token) > 0

    revoke_telegram_deep_link(context)

    assert nil == Telegram.UserToken.by_user_id(context.user.id)
  end

  test "revoked telegram deep link does not set up chat id", context do
    get_telegram_deep_link(context)
    %Telegram.UserToken{token: user_token} = Telegram.UserToken.by_user_id(context.user.id)
    revoke_telegram_deep_link(context)

    # Simulate a call after the revoke
    simulate_telegram_deep_link_follow(context, user_token)
    # There is no telegram chat id
    assert nil == UserSettings.settings_for(context.user, force: true).telegram_chat_id
  end

  test "following the telegram deep link sets the `hasTelegramConnected` setting", context do
    get_telegram_deep_link(context)
    %Telegram.UserToken{token: user_token} = Telegram.UserToken.by_user_id(context.user.id)
    simulate_telegram_deep_link_follow(context, user_token)

    %{"settings" => %{"hasTelegramConnected" => has_telegram_connected}} =
      gql_user_settings(context)

    assert has_telegram_connected == true
  end

  # Private functions

  defp get_telegram_deep_link(context) do
    query = """
    {
      getTelegramDeepLink
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "getTelegramDeepLink"))

    json_response(result, 200)["data"]["getTelegramDeepLink"]
  end

  defp revoke_telegram_deep_link(context) do
    mutation = """
    mutation{
      revokeTelegramDeepLink
    }
    """

    result =
      context.conn
      |> post("/graphql", mutation_skeleton(mutation))

    json_response(result, 200)["data"]["revokeTelegramDeepLink"]
  end

  defp simulate_telegram_deep_link_follow(context, user_token) do
    response = %{
      "message" => %{
        "chat" => %{
          "first_name" => "TestName",
          "id" => @telegram_chat_id,
          "last_name" => "TestFamilyName",
          "type" => "private",
          "username" => "test_username"
        },
        "date" => 1_547_739_610,
        "entities" => [%{"length" => 6, "offset" => 0, "type" => "bot_command"}],
        "from" => %{
          "first_name" => "TestName",
          "id" => @telegram_chat_id,
          "is_bot" => false,
          "language_code" => "en",
          "last_name" => "Test",
          "username" => "test_username"
        },
        "message_id" => 45,
        "text" => "/start #{user_token}"
      },
      "update_id" => 268_889_666
    }

    context.conn
    |> post("/telegram/#{@telegram_endpoint}", response)
  end

  defp gql_user_settings(context) do
    query = """
    {
      currentUser{
        settings{
          hasTelegramConnected
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "currentUser"))

    json_response(result, 200)["data"]["currentUser"]
  end
end
