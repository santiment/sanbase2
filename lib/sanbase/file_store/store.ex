defmodule Sanbase.FileStore do
  use Waffle.Definition

  @versions [:original]
  @acl :public_read
  @extension_whitelist ~w(.jpg .jpeg .gif .png .pdf .csv .mp4)
  @max_file_size 10 * 1024 * 1024
  @admin_max_file_size 20 * 1024 * 1024
  @cache_max_age 2_592_000

  def allowed_extensions(), do: @extension_whitelist
  def allowed_file_size(), do: div(max_file_size(), 1024 * 1024)

  @doc ~s"""
  Validate the file size and extension.

  On the admin pod the allowed file size is bigger to uploading
  bigger reports while not allowing users to upload too big images.
  """
  def validate({file, _}) do
    cond do
      not allowed_extension?(file) -> {:error, "invalid_extension"}
      in_memory_file?(file) -> true
      not allowed_size?(file) -> {:error, "file_too_large"}
      true -> true
    end
  end

  @doc ~s"""
    Generate a filename. The generated file name is in the format `scope_timestamp_name`
    where scope is explicitly passed from outside. That can be some randomly generated
    string, the hash of the file or something else.
  """
  def filename(_version, {file, scope}) do
    file_name = Path.basename(file.file_name, Path.extname(file.file_name))
    "#{scope}_#{file_name}"
  end

  def s3_object_headers(_version, {_file, _scope}) do
    [cache_control: "max-age=#{@cache_max_age}"]
  end

  # Helper functions

  defp allowed_extension?(file) do
    extension = file.file_name |> Path.extname() |> String.downcase()
    Enum.member?(@extension_whitelist, extension)
  end

  defp max_file_size() do
    if System.get_env("CONTAINER_TYPE") in ["all", "admin"] do
      @admin_max_file_size
    else
      @max_file_size
    end
  end

  defp allowed_size?(file) do
    max_file_size = max_file_size()

    case File.stat(file.path) do
      {:ok, %{size: size}} when size <= max_file_size -> true
      _ -> false
    end
  end

  defp in_memory_file?(file) do
    !file.path
  end
end
