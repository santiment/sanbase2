defmodule Sanbase.Discord.ThreadAiContext do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  schema "thread_ai_context" do
    field(:discord_user, :string)
    field(:guild_id, :string)
    field(:guild_name, :string)
    field(:channel_id, :string)
    field(:channel_name, :string)
    field(:thread_id, :string)
    field(:thread_name, :string)
    field(:question, :string)
    field(:answer, :string)
    field(:votes_pos, :integer, default: 0)
    field(:votes_neg, :integer, default: 0)
    field(:elapsed_time, :float)
    field(:tokens_request, :integer)
    field(:tokens_response, :integer)
    field(:tokens_total, :integer)
    field(:error_message, :string)
    field(:total_cost, :float)

    timestamps()
  end

  @doc false
  def changeset(thread_ai_context, attrs) do
    thread_ai_context
    |> cast(attrs, [
      :discord_user,
      :guild_id,
      :guild_name,
      :channel_id,
      :channel_name,
      :thread_id,
      :thread_name,
      :question,
      :answer,
      :votes_pos,
      :votes_neg,
      :elapsed_time,
      :tokens_request,
      :tokens_response,
      :tokens_total,
      :error_message,
      :total_cost
    ])
    |> validate_required([
      :discord_user,
      :guild_id,
      :guild_name,
      :channel_id,
      :channel_name,
      :thread_id,
      :thread_name,
      :question,
      :votes_pos,
      :votes_neg
    ])
  end

  def create(params) do
    changeset(%__MODULE__{}, params)
    |> Repo.insert()
  end

  def by_id(id) do
    query =
      from(c in __MODULE__,
        where: c.id == ^id
      )

    Repo.one(query)
  end

  def fetch_recent_history(discord_user, thread_id, limit) do
    query =
      from(c in __MODULE__,
        where: c.discord_user == ^discord_user and c.thread_id == ^thread_id,
        order_by: [desc: c.inserted_at],
        limit: ^limit
      )

    Repo.all(query)
  end

  def fetch_history_context(params, limit) do
    fetch_recent_history(params.discord_user, params.thread_id, limit)
    |> Enum.reverse()
    |> Enum.map(fn history ->
      [%{role: "user", content: history.question}, %{role: "assistant", content: history.answer}]
    end)
    |> List.flatten()
  end

  def increment_vote_pos_by_id(id) do
    query =
      from(c in __MODULE__,
        where: c.id == ^id,
        update: [inc: [votes_pos: 1]]
      )

    Repo.update_all(query, [])
  end

  def increment_vote_neg_by_id(id) do
    query =
      from(c in __MODULE__,
        where: c.id == ^id,
        update: [inc: [votes_neg: 1]]
      )

    Repo.update_all(query, [])
  end
end
