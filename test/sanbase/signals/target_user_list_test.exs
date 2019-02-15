defmodule SanbaseWeb.Graphql.UserListTest do
  use Sanbase.DataCase, async: false
  alias Sanbase.UserLists.UserList
  alias Sanbase.Signals.UserTrigger

  import Sanbase.Factory
  import ExUnit.CaptureLog

  setup do
    user = insert(:user)

    p1 =
      insert(:project, %{
        name: "Santiment",
        ticker: "SAN",
        coinmarketcap_id: "santiment",
        main_contract_address: "0x123123"
      })

    p2 =
      insert(:project, %{
        name: "Maker",
        ticker: "MKR",
        coinmarketcap_id: "maker",
        main_contract_address: "0x321321321"
      })

    {:ok, user_list} = UserList.create_user_list(user, %{name: "my_user_list", color: :green})

    UserList.update_user_list(%{
      id: user_list.id,
      list_items: [%{project_id: p1.id}, %{project_id: p2.id}]
    })

    [user: user, project1: p1, project2: p2, user_list: user_list]
  end

  test "create trigger with a single target", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: "santiment",
      channel: "telegram",
      above: 300.0,
      below: 200.0,
      repeating: false
    }

    {:ok, _trigger} =
      UserTrigger.create_user_trigger(context.user, %{
        title: "Santiment Absolute price",
        description: "The price goes above $300 or below $200",
        is_public: true,
        settings: trigger_settings
      })
  end

  test "create trigger with a single non-string target fails", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: 12,
      channel: "telegram",
      above: 300.0,
      below: 200.0,
      repeating: false
    }

    assert capture_log(fn ->
             assert {:error, "Trigger structure is invalid"} ==
                      UserTrigger.create_user_trigger(context.user, %{
                        title: "Not a valid signal",
                        is_public: true,
                        settings: trigger_settings
                      })
           end) =~
             ~s/UserTrigger struct is not valid: [{:error, :target, :by, "12 is not a valid target"}]/
  end

  test "create trigger with user_list target", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: %{user_list: context.user_list.id},
      channel: "telegram",
      above: 300.0,
      below: 200.0,
      repeating: false
    }

    {:ok, _trigger} =
      UserTrigger.create_user_trigger(context.user, %{
        title: "Absolute price for a user list",
        is_public: true,
        settings: trigger_settings
      })
  end

  test "create trigger with lists of slugs target", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: ["santiment", "ethereum", "bitcoin"],
      channel: "telegram",
      above: 300.0,
      below: 200.0,
      repeating: false
    }

    {:ok, _trigger} =
      UserTrigger.create_user_trigger(context.user, %{
        title: "Absolute price for a list of slugs",
        is_public: true,
        settings: trigger_settings
      })
  end

  test "create trigger with lists of slugs that contain non-strings fails", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: ["santiment", "ethereum", "bitcoin", 12],
      channel: "telegram",
      above: 300.0,
      below: 200.0,
      repeating: false
    }

    capture_log(fn ->
      assert {:error, "Trigger structure is invalid"} ==
               UserTrigger.create_user_trigger(context.user, %{
                 title: "Not a valid signal, too",
                 is_public: true,
                 settings: trigger_settings
               })
    end) =~
      ~s/UserTrigger struct is not valid: [{:error, :target, :by, "The target list contains elements that are not string"}]/
  end

  test "non valid target fails", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: %{user_list: [1, 2, 3]},
      channel: "telegram",
      above: 300.0,
      below: 200.0,
      repeating: false
    }

    assert capture_log(fn ->
             assert {:error, "Trigger structure is invalid"} ==
                      UserTrigger.create_user_trigger(context.user, %{
                        title: "Yet another not valid settings",
                        is_public: true,
                        settings: trigger_settings
                      })
           end) =~
             ~s/UserTrigger struct is not valid: [{:error, :target, :by, "%{user_list: [1, 2, 3]} is not a valid target"}]/
  end
end
