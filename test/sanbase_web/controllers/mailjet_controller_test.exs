defmodule SanbaseWeb.MailjetControllerTest do
  use SanbaseWeb.ConnCase, async: false

  import Mox
  import Sanbase.Factory
  alias Sanbase.Accounts.UserSettings

  setup :verify_on_exit!

  describe "webhook/2" do
    setup do
      user = insert(:user, email: "test@example.com")

      insert(:user_settings,
        user: user,
        settings: %{is_subscribed_metric_updates: true}
      )

      # Set up the mock to allow any process to call unsubscribe
      # This handles the asynchronous EventBus subscriber
      Mox.allow(
        Sanbase.Email.MockMailjetApi,
        self(),
        Process.whereis(Sanbase.EventBus.UserEventsSubscriber)
      )

      %{user: user}
    end

    test "handles valid unsubscribe event", %{conn: conn, user: user} do
      Mox.expect(Sanbase.Email.MockMailjetApi, :unsubscribe, fn _, _ -> :ok end)

      params = %{
        "event" => "unsub",
        "email" => user.email,
        "mj_list_id" => 10_327_883,
        "time" => 1_433_334_941,
        "MessageID" => 20_547_674_933_128_000,
        "Message_GUID" => "1ab23cd4-e567-8901-2345-6789f0gh1i2j",
        "CustomID" => "helloworld"
      }

      conn = post(conn, ~p"/mailjet/webhook", params)

      # Check that we got a 200 OK response
      assert response(conn, 200) == ""

      # Wait a short time for the EventBus to process the event
      :timer.sleep(100)

      # Verify the user's settings were updated
      updated_settings = UserSettings.settings_for(user, force: true)
      refute updated_settings.is_subscribed_metric_updates
    end

    test "returns 200 even for invalid events", %{conn: conn} do
      # Missing email
      params = %{
        "event" => "unsub",
        "mj_list_id" => 10_327_883
      }

      conn = post(conn, ~p"/mailjet/webhook", params)
      assert response(conn, 200) == ""

      # Missing event type
      params = %{
        "email" => "test@example.com",
        "mj_list_id" => 10_327_883
      }

      conn = post(conn, ~p"/mailjet/webhook", params)
      assert response(conn, 200) == ""

      # Wrong event type
      params = %{
        "event" => "open",
        "email" => "test@example.com",
        "mj_list_id" => 10_327_883
      }

      conn = post(conn, ~p"/mailjet/webhook", params)
      assert response(conn, 200) == ""
    end

    test "handles non-existent user", %{conn: conn} do
      params = %{
        "event" => "unsub",
        "email" => "nonexistent@example.com",
        "mj_list_id" => 10_327_883
      }

      conn = post(conn, ~p"/mailjet/webhook", params)
      assert response(conn, 200) == ""
    end

    test "handles unknown list ID", %{conn: conn} do
      params = %{
        "event" => "unsub",
        "email" => "test@example.com",
        "mj_list_id" => 99999
      }

      conn = post(conn, ~p"/mailjet/webhook", params)
      assert response(conn, 200) == ""
    end
  end
end
