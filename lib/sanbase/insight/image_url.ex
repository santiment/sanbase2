defmodule Sanbase.Insight.ImageUrl do
  @moduledoc """
  Shared module for extracting Sanbase-hosted image URLs from insight text.
  Used by Post.images_cast to link images to posts via DB associations.
  """

  case Application.compile_env(:sanbase, :env) do
    :test ->
      def regex() do
        storage_dir = Application.get_env(:waffle, :storage_dir)

        storage_dir =
          if String.last(storage_dir) != "/", do: storage_dir <> "/", else: storage_dir

        Regex.compile!(~s{#{storage_dir}[^\s"<>]+(?:\.jpg|\.png|\.gif|\.jpeg)})
      end

    _ ->
      def regex(),
        do:
          ~r{https://[a-zA-Z0-9\-\.]*sanbase-images.s3\.amazonaws\.com/[^\s"<>]+(?:\.jpg|\.png|\.gif|\.jpeg)}
  end

  @doc """
  Extract Sanbase-hosted image URLs from text.
  """
  def extract_from_text(nil), do: []
  def extract_from_text(""), do: []

  def extract_from_text(text) do
    Regex.scan(regex(), text, capture: :first)
    |> List.flatten()
  end
end
