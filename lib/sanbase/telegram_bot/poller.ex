defmodule Sanbase.TelegramBot.Poller do
  @moduledoc """
  Long-polling loop for the Telegram Q&A bot.

  Fetches updates via `getUpdates` (no public URL/webhook needed) and handles
  each update in a supervised task so a slow AI server call never blocks
  polling. Started only when `TELEGRAM_QA_BOT_TOKEN` is set, in the same
  container as the Discord bot (queries).
  """

  use GenServer

  require Logger

  alias Sanbase.TelegramBot.Api
  alias Sanbase.TelegramBot.MessageHandler

  @poll_error_backoff 5_000
  @setup_retry_interval 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{offset: nil, bot: nil}, {:continue, :setup}}
  end

  @impl true
  def handle_continue(:setup, state) do
    # A token can have either a webhook or a getUpdates consumer, not both
    Api.delete_webhook()

    case Api.get_me() do
      {:ok, %{"id" => id, "username" => username}} ->
        Logger.info("[TelegramQABot] starting to poll as @#{username}")
        send(self(), :poll)
        {:noreply, %{state | bot: %{id: id, username: username}}}

      {:error, error} ->
        Logger.error(
          "[TelegramQABot] getMe failed: #{inspect(error)}. Retrying in #{@setup_retry_interval}ms"
        )

        Process.send_after(self(), :retry_setup, @setup_retry_interval)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:retry_setup, state) do
    {:noreply, state, {:continue, :setup}}
  end

  @impl true
  def handle_info(:poll, %{bot: bot} = state) do
    case Api.get_updates(state.offset) do
      {:ok, updates} when is_list(updates) ->
        Enum.each(updates, fn update ->
          Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
            MessageHandler.handle_update(update, bot)
          end)
        end)

        send(self(), :poll)
        {:noreply, %{state | offset: next_offset(updates, state.offset)}}

      {:error, _error} ->
        Process.send_after(self(), :poll, @poll_error_backoff)
        {:noreply, state}
    end
  end

  defp next_offset([], offset), do: offset

  defp next_offset(updates, _offset) do
    %{"update_id" => update_id} = List.last(updates)
    update_id + 1
  end
end
