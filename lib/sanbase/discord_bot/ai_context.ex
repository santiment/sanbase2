defmodule Sanbase.DiscordBot.AiContext do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @server_limit_per_day 10
  @pro_user_limit_per_day 20

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
    timestamps()
  end

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
      :route
    ])
    |> validate_required([:discord_user, :guild_id, :channel_id, :question])
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

  def fetch_recent_history(thread_id, limit) do
    query =
      from(c in __MODULE__,
        where: c.thread_id == ^thread_id,
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

    query_for_server =
      from(c in __MODULE__,
        where:
          c.command == "!ai" and c.guild_id == ^args.guild_id and
            c.user_is_pro != true and fragment("?::date = ?", c.inserted_at, ^start_of_day),
        select: count(c.id)
      )

    query_for_pro_user =
      from(c in __MODULE__,
        where:
          c.command == "!ai" and c.discord_user == ^args.discord_user and
            c.user_is_pro == true and fragment("?::date = ?", c.inserted_at, ^start_of_day),
        select: count(c.id)
      )

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

  defp convert_to_h_m(seconds) do
    hours = div(seconds, 3600)
    remainder = rem(seconds, 3600)
    minutes = div(remainder, 60)

    "#{hours} hours #{minutes} minutes"
  end
end
