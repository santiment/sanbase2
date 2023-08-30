defmodule Sanbase.Discord.AiGenCode do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  schema "ai_gen_code" do
    field(:question, :string)
    field(:answer, :string)
    field(:parent_id, :id)
    field(:program, :string)
    field(:program_result, :string)
    field(:discord_user, :string)
    field(:guild_id, :string)
    field(:guild_name, :string)
    field(:channel_id, :string)
    field(:channel_name, :string)
    field(:elapsed_time, :integer)
    field(:changes, :string)
    field(:is_saved_vs, :boolean, default: false)
    field(:is_from_vs, :boolean, default: false)

    timestamps()
  end

  @doc false
  def changeset(ai_gen_code, attrs) do
    ai_gen_code
    |> cast(attrs, [
      :question,
      :answer,
      :parent_id,
      :program,
      :program_result,
      :discord_user,
      :guild_id,
      :guild_name,
      :channel_id,
      :channel_name,
      :elapsed_time,
      :changes,
      :is_saved_vs,
      :is_from_vs
    ])
    |> validate_required([:question, :answer, :program, :program_result, :elapsed_time])
  end

  def create(params) do
    changeset(%__MODULE__{}, params)
    |> Repo.insert()
  end

  def change(ai_gen_code, params) do
    changeset(ai_gen_code, params)
    |> Repo.update()
  end

  def by_id(id) do
    query = from(c in __MODULE__, where: c.id == ^id)

    Repo.one(query)
  end
end
