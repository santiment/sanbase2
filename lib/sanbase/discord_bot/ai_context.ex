defmodule Sanbase.DiscordBot.AiContext do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @server_limit_per_day 10
  @pro_user_limit_per_day 20

  # Commands that count towards the daily limit.
  #
  # `command` is derived from the answer's route: "!ai" for twitter-routed
  # answers, "!thread" for everything else. Counting only "!ai" meant academy,
  # metric and dialogue questions - the large majority - were never counted, so
  # the limit almost never applied.
  @rate_limited_commands ["!ai", "!thread"]

  schema "ai_context" do
    field(:answer, :string)
    field(:discord_user, :string)
    field(:question, :string)
    field(:guild_id, :string)
    field(:guild_name, :string)
    field(:channel_id, :string)
    field(:channel_name, :string)
    field(:elapsed_time, :float)
    field(:tokens_request, :integer)
    field(:tokens_response, :integer)
    field(:tokens_total, :integer)
    field(:error_message, :string)
    field(:total_cost, :float)
    field(:command, :string)
    field(:prompt, :string)
    field(:user_is_pro, :boolean, default: false)
    field(:thread_id, :string)
    field(:thread_name, :string)
    field(:votes, :map, default: %{})
    field(:route, :map, default: %{})
    field(:function_called, :string)

    # Diagnostics for a turn. A row used to exist only when the AI server
    # answered successfully, so failures were invisible here.
    #
    # status:            "ok" | "degraded" (a fallback produced the answer) |
    #                    "error" (nothing usable came back)
    # qa_engine:         which QA engine answered, "v1" or "v2"
    # v2_fallback:       the v2 orchestrator raised and v1 answered instead
    # rephrased_question the standalone question sent downstream, when rewritten
    # tools_used:        tools the v2 orchestrator called
    # langfuse_trace_id: links the row to its trace
    field(:status, :string, default: "ok")
    field(:qa_engine, :string)
    field(:v2_fallback, :boolean, default: false)
    field(:rephrased_question, :string)
    field(:tools_used, {:array, :string}, default: [])
    field(:langfuse_trace_id, :string)

    # Review diagnostics, read by the AI bot review admin page.
    #
    # delivery_status: "sent" | "failed" - whether the answer reached the chat.
    #                  Set after posting; nil when nothing was posted.
    # delivery_error:  why posting failed
    # tool_issues:     problems the AI server reports per tool, e.g.
    #                  "search_tweets:empty" or "fetch_metric_data_tool:error"
    field(:delivery_status, :string)
    field(:delivery_error, :string)
    field(:tool_issues, {:array, :string}, default: [])

    timestamps()
  end

  @doc "A turn that produced a usable answer."
  def ok_status(), do: "ok"

  @doc "A turn answered by a fallback path rather than the intended one."
  def degraded_status(), do: "degraded"

  @doc "A turn that produced no usable answer."
  def error_status(), do: "error"

  @doc false
  def changeset(ai_context, attrs) do
    ai_context
    |> cast(attrs, [
      :discord_user,
      :guild_id,
      :guild_name,
      :channel_id,
      :channel_name,
      :question,
      :answer,
      :elapsed_time,
      :tokens_request,
      :tokens_response,
      :tokens_total,
      :error_message,
      :total_cost,
      :command,
      :prompt,
      :user_is_pro,
      :thread_id,
      :thread_name,
      :votes,
      :route,
      :function_called,
      :status,
      :qa_engine,
      :v2_fallback,
      :rephrased_question,
      :tools_used,
      :langfuse_trace_id,
      :delivery_status,
      :delivery_error,
      :tool_issues
    ])
    |> validate_required([:discord_user, :guild_id, :channel_id, :question])
    |> validate_inclusion(:status, ["ok", "degraded", "error"])
    |> validate_inclusion(:delivery_status, ["sent", "failed"])
  end

  def by_id(id) do
    query =
      from(c in __MODULE__,
        where: c.id == ^id
      )

    Repo.one(query)
  end

  def create(params) do
    changeset(%__MODULE__{}, params)
    |> Repo.insert()
  end

  @doc """
  Recent turns of a conversation, newest first.

  Errored turns are skipped: they carry no answer, and feeding a failure back
  into the next prompt makes the model apologise for something the user never
  saw. Degraded turns are kept, since the user did see those answers.
  """
  def fetch_recent_history(thread_id, limit) do
    query =
      from(c in __MODULE__,
        where:
          c.thread_id == ^thread_id and
            (is_nil(c.status) or c.status != "error") and
            not is_nil(c.answer),
        order_by: [desc: c.inserted_at],
        limit: ^limit
      )

    Repo.all(query)
  end

  def fetch_history_context(params, limit) do
    fetch_recent_history(params.thread_id, limit)
    |> Enum.reverse()
    |> Enum.map(fn history ->
      [%{role: "user", content: history.question}, %{role: "assistant", content: history.answer}]
    end)
    |> List.flatten()
  end

  @doc """
  Records whether the answer of a turn was posted to the chat.

  `:ok` marks it sent; `{:error, reason}` marks it failed and keeps the reason.
  """
  def record_delivery(%__MODULE__{} = ai_context, :ok) do
    ai_context
    |> changeset(%{delivery_status: "sent", delivery_error: nil})
    |> Repo.update()
  end

  def record_delivery(%__MODULE__{} = ai_context, {:error, reason}) do
    ai_context
    |> changeset(%{delivery_status: "failed", delivery_error: delivery_error(reason)})
    |> Repo.update()
  end

  defp delivery_error(reason) when is_binary(reason), do: String.slice(reason, 0, 2000)
  defp delivery_error(reason), do: reason |> inspect() |> String.slice(0, 2000)

  def add_vote(context_id, new_vote) do
    context = Repo.get!(__MODULE__, context_id)

    updated_votes = Map.merge(context.votes, new_vote)

    changeset(context, %{votes: updated_votes})
    |> Repo.update()
  end

  def check_limits(args) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    start_of_day = DateTime.to_date(now)
    start_of_next_day = Date.add(start_of_day, 1)

    query_for_server = query_for_server(args, start_of_day)
    query_for_pro_user = query_for_pro_user(args, start_of_day)
    server_query_count = Repo.one(query_for_server)
    pro_user_query_count = Repo.one(query_for_pro_user)

    time_left =
      DateTime.diff(
        DateTime.from_naive!(NaiveDateTime.new!(start_of_next_day, ~T[00:00:00]), "Etc/UTC"),
        now,
        :second
      )
      |> convert_to_h_m()

    cond do
      !args.user_is_pro and server_query_count >= @server_limit_per_day ->
        {:error, :eserverlimit, time_left}

      args.user_is_pro and pro_user_query_count >= @pro_user_limit_per_day ->
        {:error, :eprolimit, time_left}

      true ->
        :ok
    end
  end

  # A turn that errored cost the user nothing, so it must not eat their daily
  # quota. Now that failures are recorded, an outage would otherwise lock a chat
  # out for the rest of the day.
  defp query_for_server(args, start_of_day) do
    from(c in __MODULE__,
      where:
        c.command in @rate_limited_commands and c.guild_id == ^args.guild_id and
          c.user_is_pro != true and fragment("?::date = ?", c.inserted_at, ^start_of_day) and
          (is_nil(c.status) or c.status != "error"),
      select: count(c.id)
    )
  end

  defp query_for_pro_user(args, start_of_day) do
    from(c in __MODULE__,
      where:
        c.command in @rate_limited_commands and c.guild_id == ^args.guild_id and
          c.user_is_pro == true and fragment("?::date = ?", c.inserted_at, ^start_of_day) and
          (is_nil(c.status) or c.status != "error"),
      select: count(c.id)
    )
  end

  defp convert_to_h_m(seconds) do
    hours = div(seconds, 3600)
    remainder = rem(seconds, 3600)
    minutes = div(remainder, 60)

    "#{hours} hours #{minutes} minutes"
  end
end
