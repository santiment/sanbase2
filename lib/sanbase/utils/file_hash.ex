defmodule Sanbase.Utils.FileHash do
  @hash_algorithm :sha256

  @doc ~s"""
  Receives a filepath and calculates hash using sha256 algorithm.
  """
  def calculate(filepath) do
    try do
      hash =
        File.stream!(filepath, 8192, [])
        |> Enum.reduce(:crypto.hash_init(@hash_algorithm), fn line, acc ->
          :crypto.hash_update(acc, line)
        end)
        |> :crypto.hash_final()
        |> Base.encode16()
        |> String.downcase()

      {:ok, hash}
    rescue
      error in File.Error ->
        %{reason: reason} = error
        {:error, "Error calculating file's content hash. Reason: #{reason}"}
    end
  end

  def algorithm do
    @hash_algorithm
  end
end
