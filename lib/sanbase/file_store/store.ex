defmodule Sanbase.FileStore do
  use Waffle.Definition

  @versions [:original]
  @acl :public_read
  @extension_whitelist ~w(.jpg .jpeg .gif .png .pdf .csv)
  @max_file_size 5 * 1024 * 1024
  @cache_max_age 2_592_000
  @doc ~s"""
    Whitelist file extensions. Now allowing only images.
  """
  def validate({file, _}) do
    allowed_extenstion?(file) && (in_memory_file?(file) || allowed_size?(file))
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

  defp allowed_extenstion?(file) do
    @extension_whitelist
    |> Enum.member?(Path.extname(file.file_name |> String.downcase()))
  end

  defp allowed_size?(file) do
    case File.stat(file.path) do
      {:ok, %{size: size}} when size <= @max_file_size ->
        true

      _ ->
        false
    end
  end

  defp in_memory_file?(file) do
    !file.path
  end
end
