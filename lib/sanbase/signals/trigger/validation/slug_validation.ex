defmodule Sanbase.Signal.Validation.Slug do
  alias Sanbase.Model.Project

  def valid_slug?(%{slug: slug}) when is_binary(slug) do
    slug
    |> Project.id_by_slug()
    |> case do
      id when is_integer(id) and id > 0 -> :ok
      _ -> {:error, "#{inspect(slug)} is not a valid slug"}
    end
  end

  def valid_slug?(slug) do
    {:error,
     "#{inspect(slug)} is not a valid slug. A valid slug is a map with a single slug key and string value"}
  end
end
