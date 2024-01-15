defmodule Sanbase.DiscordBot.GptRouter do
  use Ecto.Schema
  import Ecto.Changeset

  schema "gpt_router" do
    field(:question, :string)
    field(:route, :string)
    field(:scores, :map, default: %{})
    field(:error, :string)
    field(:elapsed_time, :integer)
    field(:timeframe, :integer, default: -1)
    field(:sentiment, :boolean, default: false)
    field(:projects, {:array, :string}, default: [])

    timestamps()
  end

  @doc false
  def changeset(gpt_router, attrs) do
    gpt_router
    |> cast(attrs, [
      :question,
      :route,
      :scores,
      :error,
      :elapsed_time,
      :timeframe,
      :sentiment,
      :projects
    ])
    |> validate_required([:question])
  end

  def create(attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Sanbase.Repo.insert()
  end
end
