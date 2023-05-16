defmodule Sanbase.Discord.AiContext do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Repo

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
      :command
    ])
    |> validate_required([:discord_user, :guild_id, :channel_id, :question, :command])
  end

  def create(params) do
    changeset(%__MODULE__{}, params)
    |> Repo.insert()
  end
end
