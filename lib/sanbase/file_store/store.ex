defmodule Sanbase.FileStore do
  use Arc.Definition

  @versions [:original]
  @acl :public_read

  @doc ~s"""
    Whitelist file extensions. Now allowing only images.
  """
  def validate({file, _}) do
    ~w(.jpg .jpeg .gif .png)
    |> Enum.member?(Path.extname(file.file_name |> String.downcase()))
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
end
