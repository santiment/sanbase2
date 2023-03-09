defmodule Sanbase.Cryptocompare.ExporterProgress do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  schema "cryptocompare_exporter_progress" do
    field(:key, :string)
    field(:queue, :string)
    field(:min_timestamp, :integer)
    field(:max_timestamp, :integer)

    timestamps()
  end

  @doc false
  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [:key, :queue, :min_timestamp, :max_timestamp])
    |> validate_required([:key, :queue, :min_timestamp, :max_timestamp])
    |> unique_constraint([:key, :queue])
  end

  def create_or_update(key, queue, min_timestamp, max_timestamp) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get, fn _repo, _changes ->
      query = from(ep in __MODULE__, where: ep.key == ^key and ep.queue == ^queue)
      {:ok, Sanbase.Repo.one(query)}
    end)
    |> Ecto.Multi.run(:create_or_update, fn _repo, %{get: progress} ->
      case progress do
        nil ->
          changeset(%__MODULE__{}, %{
            key: key,
            queue: queue,
            min_timestamp: min_timestamp,
            max_timestamp: max_timestamp
          })
          |> Sanbase.Repo.insert()

        %__MODULE__{} = progress ->
          changeset(progress, %{
            min_timestamp: Enum.min([progress.min_timestamp, min_timestamp]),
            max_timestamp: Enum.max([progress.max_timestamp, max_timestamp])
          })
          |> Sanbase.Repo.update()
      end
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, %{create_or_update: result}} -> {:ok, result}
      {:error, _failed_op, error, _changes} -> {:error, error}
    end
  end

  def get_timestamps(key, queue) do
    from(progress in __MODULE__,
      where: progress.key == ^key and progress.queue == ^queue,
      select: {progress.min_timestamp, progress.max_timestamp}
    )
    |> Sanbase.Repo.one()
  end
end
