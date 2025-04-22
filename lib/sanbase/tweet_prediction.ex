defmodule Sanbase.TweetPrediction do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "tweet_predictions" do
    field(:tweet_id, :string)
    field(:timestamp, :utc_datetime)
    field(:text, :string)
    field(:url, :string)
    field(:is_prediction, :boolean)
    field(:is_interesting, :boolean, default: false)
    field(:screen_name, :string)

    timestamps()
  end

  @required_fields [:tweet_id, :timestamp, :text, :url, :is_prediction, :screen_name]
  @optional_fields [:is_interesting]

  @doc """
  Creates a changeset for a tweet prediction.
  """
  def changeset(prediction, attrs) do
    prediction
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:tweet_id)
  end

  @doc """
  Creates a new tweet prediction record.
  """
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Sanbase.Repo.insert()
  end

  @doc """
  Retrieves all classified tweet IDs.
  """
  def list_classified_tweet_ids do
    __MODULE__
    |> select([p], p.tweet_id)
    |> Sanbase.Repo.all()
    |> MapSet.new()
  end

  @doc """
  Retrieves all tweet predictions.
  """
  def list do
    Sanbase.Repo.all(__MODULE__)
  end

  @doc """
  Count the total number of classified tweets.
  """
  def count_total do
    __MODULE__
    |> Sanbase.Repo.aggregate(:count, :id)
  end

  @doc """
  Count the number of tweets classified as predictions.
  """
  def count_predictions do
    __MODULE__
    |> where([p], p.is_prediction == true)
    |> Sanbase.Repo.aggregate(:count, :id)
  end

  @doc """
  Count the number of tweets classified as not predictions.
  """
  def count_not_predictions do
    __MODULE__
    |> where([p], p.is_prediction == false)
    |> Sanbase.Repo.aggregate(:count, :id)
  end

  @doc """
  Returns a map with the counts of total, predictions, and not predictions.
  """
  def get_counts do
    %{
      total: count_total(),
      predictions: count_predictions(),
      not_predictions: count_not_predictions()
    }
  end
end
