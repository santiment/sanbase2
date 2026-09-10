defmodule Sanbase.DiscordBot.AiServerTest do
  use Sanbase.DataCase, async: false

  import Ecto.Query

  alias Sanbase.DiscordBot.AiContext
  alias Sanbase.DiscordBot.AiServer
  alias Sanbase.Repo

  @metadata %{
    discord_user: "tg:someone",
    guild_id: "tg_-100123",
    guild_name: "Santiment",
    channel_id: "-100123",
    channel_name: "Santiment",
    thread_id: "tg_-100123_m1",
    thread_name: nil,
    msg_id: 1,
    user_is_pro: false,
    platform: "telegram"
  }

  setup do
    original = System.get_env("AI_SERVER_URL")
    # Refused immediately, so the failure path runs without waiting on a timeout.
    System.put_env("AI_SERVER_URL", "http://127.0.0.1:1")

    on_exit(fn ->
      case original do
        nil -> System.delete_env("AI_SERVER_URL")
        value -> System.put_env("AI_SERVER_URL", value)
      end
    end)

    :ok
  end

  test "a failed question is recorded instead of vanishing" do
    # Before this, the error branch returned without touching the database, so a
    # question that failed left no row at all and only appeared in the logs.
    assert {:error, _reason} =
             AiServer.answer("первые 10 из списка", @metadata)

    row =
      from(c in AiContext, where: c.guild_id == ^@metadata.guild_id, order_by: [desc: c.id])
      |> Repo.one!()

    assert row.question == "первые 10 из списка"
    assert row.status == "error"
    assert row.error_message =~ "ai_server_transport_"
    assert row.discord_user == "tg:someone"
    assert is_nil(row.answer)
  end

  test "a recorded failure does not become conversation context" do
    assert {:error, _reason} = AiServer.answer("failing question", @metadata)

    assert AiContext.fetch_history_context(@metadata, 10) == []
  end
end
