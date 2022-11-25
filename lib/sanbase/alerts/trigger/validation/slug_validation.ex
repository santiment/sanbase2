defmodule Sanbase.Alert.Validation.Slug do
  alias Sanbase.Project

  @doc ~s"""
  Check if there is a project with the same slug as the provided one.
  """
  @spec valid_slug?(map()) :: :ok | {:error, String.t()}
  def valid_slug?(%{slug: slug}) when is_binary(slug) do
    slug
    |> Project.id_by_slug()
    |> case do
      id when is_integer(id) and id > 0 -> :ok
      _ -> {:error, ~s/"#{slug}" is not a valid slug/}
    end
  end

  def valid_slug?(slug) do
    {:error,
     "#{inspect(slug)} is not a valid slug. A valid slug is a map with a single slug key and string value"}
  end
end
