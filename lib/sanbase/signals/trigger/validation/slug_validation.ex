defmodule Sanbase.Signal.Validation.Slug do
  def valid_slug?(%{slug: slug}) when is_binary(slug), do: :ok

  def valid_slug?(slug) do
    {:error,
     "#{inspect(slug)} is not a valid slug. A valid slug is a map with a single slug key and string value"}
  end
end
