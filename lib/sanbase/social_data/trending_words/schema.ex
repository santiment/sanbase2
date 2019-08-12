defmodule Sanbase.SocialData.TrendingWords.Schema do
  use Ecto.Schema

  @table "trending_words"
  schema @table do
    field(:dt, :utc_datetime)
    field(:word, :string)
    field(:volume, :float)
    field(:volume_normalized, :float)
    field(:unqiue_users, :integer)
    field(:score, :float)
    field(:source, :string)
    # ticker_slug
    field(:project, :string)
    field(:computed_at, :string)
  end
end
