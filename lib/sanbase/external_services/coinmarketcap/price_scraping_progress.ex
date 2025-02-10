defmodule Sanbase.ExternalServices.Coinmarketcap.PriceScrapingProgress do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  schema "price_scraping_progress" do
    field(:identifier, :string)
    field(:datetime, :naive_datetime)
    field(:source, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = progress, attrs \\ %{}) do
    progress
    |> cast(attrs, [:identifier, :datetime, :source])
    |> validate_required([:identifier, :datetime, :source])
  end

  def last_scraped(identifier, source) do
    from(progress in __MODULE__,
      where: progress.identifier == ^identifier and progress.source == ^source,
      select: progress.datetime
    )
    |> Repo.one()
    |> case do
      %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "Etc/UTC")
      _ -> nil
    end
  end

  def last_scraped_all_source(source) do
    from(progress in __MODULE__,
      where: progress.source == ^source,
      select: {progress.identifier, progress.datetime}
    )
    |> Repo.all()
    |> Map.new()
  end

  def store_progress(identifier, source, datetime) do
    (Repo.get_by(__MODULE__, identifier: identifier, source: source) || %__MODULE__{})
    |> changeset(%{identifier: identifier, source: source, datetime: datetime})
    |> Repo.insert_or_update()
  end
end
