defmodule Sanbase.Signals.PriceVolumeDiffTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Signals.{Trigger, UserTrigger, Evaluator}
  alias Sanbase.Signals.Trigger.PriceVolumeDifferenceTriggerSettings

  @ticker "SAN"
  @cmc_id "santiment"
  setup_with_mocks([
    {Sanbase.Chart, [],
     [
       build_embedded_chart: fn _, _, _, _ -> [%{image: %{url: "somelink"}}] end,
       build_embedded_chart: fn _, _, _ -> [%{image: %{url: "somelink"}}] end
     ]}
  ]) do
    Sanbase.Signals.Evaluator.Cache.clear()

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{status: 200, body: "ok"}
    end)

    user = insert(:user)
    Sanbase.Auth.UserSettings.set_telegram_chat_id(user.id, 123_123_123_123)

    Sanbase.Factory.insert(:project, %{
      name: "Santiment",
      ticker: @ticker,
      coinmarketcap_id: @cmc_id,
      main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    })

    {trigger1, trigger2} = setup_triggers(user)

    [
      user: user,
      trigger1: trigger1,
      trigger2: trigger2
    ]
  end

  test "no triggers were defined", _context do
    triggers = UserTrigger |> Sanbase.Repo.all()

    triggers
    |> Enum.each(fn t ->
      Sanbase.Repo.get!(UserTrigger, t.id)
      |> Sanbase.Repo.delete()
    end)

    triggered =
      PriceVolumeDifferenceTriggerSettings.type()
      |> UserTrigger.get_active_triggers_by_type()
      |> Evaluator.run()

    assert triggered == []
  end

  test "none of the price volume diff signals triggered", _context do
    with_mock HTTPoison, [],
      get: fn _, _, _ ->
        {:ok,
         %HTTPoison.Response{
           body: """
           [
             #{Sanbase.TechIndicatorsTestResponse.price_volume_diff_prepend_response()},
             {"price_volume_diff": 0.0001, "price_change": 0.04, "volume_change": 0.03, "timestamp": 1516752000}
           ]
           """,
           status_code: 200
         }}
      end do
      triggered =
        PriceVolumeDifferenceTriggerSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert triggered == []
    end
  end

  test "only some of price volume diff signals triggered", context do
    with_mock HTTPoison, [],
      get: fn _, _, _ ->
        {:ok,
         %HTTPoison.Response{
           body: """
           [
             #{Sanbase.TechIndicatorsTestResponse.price_volume_diff_prepend_response()},
             {"price_volume_diff": 0.01, "price_change": 0.04, "volume_change": 0.03, "timestamp": #{
             DateTime.utc_now() |> DateTime.to_unix()
           }}
           ]
           """,
           status_code: 200
         }}
      end do
      [triggered | rest] =
        PriceVolumeDifferenceTriggerSettings.type()
        |> UserTrigger.get_active_triggers_by_type()
        |> Evaluator.run()

      assert rest == []
      assert context.trigger1.id == triggered.id
      assert Trigger.triggered?(triggered.trigger) == true
    end
  end

  test "tech indicators returns :ok tuple with internal error", _context do
    with_mock HTTPoison, [],
      get: fn _, _, _ ->
        {:ok,
         %HTTPoison.Response{
           body: "Internal Server Error",
           status_code: 500
         }}
      end do
      assert capture_log(fn ->
               triggered =
                 PriceVolumeDifferenceTriggerSettings.type()
                 |> UserTrigger.get_active_triggers_by_type()
                 |> Evaluator.run()

               assert triggered == []
             end) =~ "Internal Server Error"
    end
  end

  test "tech indicators return :error tuple", _context do
    with_mock HTTPoison, [],
      get: fn _, _, _ ->
        {:error,
         %HTTPoison.Error{
           reason: :econnrefused
         }}
      end do
      assert capture_log(fn ->
               triggered =
                 PriceVolumeDifferenceTriggerSettings.type()
                 |> UserTrigger.get_active_triggers_by_type()
                 |> Evaluator.run()

               assert triggered == []
             end) =~ "econnrefused"
    end
  end

  defp setup_triggers(user) do
    trigger_settings1 = %{
      type: "price_volume_difference",
      target: %{slug: "santiment"},
      channel: "telegram",
      threshold: 0.002
    }

    trigger_settings2 = %{
      type: "price_volume_difference",
      target: %{slug: "santiment"},
      channel: "telegram",
      threshold: 0.1
    }

    {:ok, trigger1} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings1
      })

    {:ok, trigger2} =
      UserTrigger.create_user_trigger(user, %{
        title: "Generic title 2",
        is_public: true,
        cooldown: "12h",
        settings: trigger_settings2
      })

    {trigger1, trigger2}
  end
end
