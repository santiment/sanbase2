defmodule Sanbase.Utils.Temp do
  @moduledoc """
  Create temporary directories with random names.
  Replaces the `temp` package dependency.
  """

  @doc """
  Creates a temporary directory with a unique name and returns `{:ok, path}`.

  The directory is created inside `System.tmp_dir!/0`. The name is composed of
  the given prefix, a timestamp, the OS pid, and a random string to avoid
  collisions.

      iex> {:ok, path} = Sanbase.Utils.Temp.mkdir("uploads")
      iex> File.dir?(path)
      true
  """
  @spec mkdir(String.t()) :: {:ok, String.t()} | {:error, term()}
  def mkdir(prefix \\ "tmp") do
    path = generate_path(prefix)

    case File.mkdir(path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Same as `mkdir/1`, but raises on failure.
  """
  @spec mkdir!(String.t()) :: String.t()
  def mkdir!(prefix \\ "tmp") do
    case mkdir(prefix) do
      {:ok, path} -> path
      {:error, reason} -> raise "Failed to create temp directory: #{inspect(reason)}"
    end
  end

  defp generate_path(prefix) do
    name =
      [prefix, "-", timestamp(), "-", os_pid(), "-", random_string()]
      |> Enum.join()

    Path.join(System.tmp_dir!(), name)
  end

  defp timestamp do
    {ms, s, _} = :os.timestamp()
    Integer.to_string(ms * 1_000_000 + s)
  end

  defp os_pid, do: :os.getpid()

  defp random_string do
    :rand.uniform(0x100000000)
    |> Integer.to_string(36)
    |> String.downcase()
  end
end
