defmodule Sanbase.Seeds.Helpers do
  def random_date(days \\ 90) do
    day_shift = :rand.uniform(days)

    Timex.now()
    |> Timex.shift(days: -day_shift)
  end

  def random_non_neg_float(upper_limit \\ 10_000) do
    :rand.uniform() * upper_limit
  end

  def random_non_neg_integer(upper_limit \\ 10_000) do
    :rand.uniform(upper_limit)
  end
end
