defmodule Sanbase.Ecto.Common do
  import Ecto.Query

  @doc ~s"""
  Checks whether the user can create a new entity of a given type or if
  a rate limit must be applied.

  The `module` must have an `inserted_at` datetime column without a timezone.
  This is the default column of Ecto's `timestamp()`. A rate limit per
  minute, hour and day are applied. These limits are provided as the `:limits`
  key in the opts. The keys of that map are `:minute`, `:hour` and `:day`.
  Additionally, for the error message formatting the `:entity_singular` and
  `:entity_plural` keys must be present in the opts, too.
  """
  @spec has_not_reached_rate_limits?(module, non_neg_integer, Keyword.t()) ::
          {:ok, true} | {:error, String.t()}
  def has_not_reached_rate_limits?(module, user_id, opts) do
    now = NaiveDateTime.utc_now()

    map =
      from(p in module,
        where: p.user_id == ^user_id,
        select: %{
          day:
            fragment(
              "COUNT(*) FILTER (WHERE inserted_at >= ?)",
              ^NaiveDateTime.add(now, -86_400, :second)
            ),
          hour:
            fragment(
              "COUNT(*) FILTER (WHERE inserted_at >= ?)",
              ^NaiveDateTime.add(now, -3600, :second)
            ),
          minute:
            fragment(
              "COUNT(*) FILTER (WHERE inserted_at >= ?)",
              ^NaiveDateTime.add(now, -60, :second)
            )
        }
      )
      |> Sanbase.Repo.one()

    limits = Keyword.fetch!(opts, :limits)
    entity_singular = Keyword.fetch!(opts, :entity_singular)
    entity_plural = Keyword.fetch!(opts, :entity_plural)

    error_msg = fn
      1, period -> {:error, "Cannot create more than 1 #{entity_singular} per #{period}"}
      limit, period -> {:error, "Cannot create more than #{limit} #{entity_plural} per #{period}"}
    end

    cond do
      map.minute >= limits.minute -> error_msg.(limits.minute, "minute")
      map.hour >= limits.hour -> error_msg.(limits.hour, "hour")
      map.day >= limits.day -> error_msg.(limits.day, "day")
      # return an :ok tuple so it can be used inside Ecto.Multi
      true -> {:ok, true}
    end
  end
end
