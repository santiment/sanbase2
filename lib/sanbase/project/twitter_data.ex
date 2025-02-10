defmodule Sanbase.Project.TwitterData do
  @moduledoc false
  alias Sanbase.Project

  def link_to_handle("https://twitter.com/" <> twitter_name), do: twitter_name |> String.split("/") |> hd()

  def link_to_handle("https://x.com/" <> twitter_name), do: twitter_name |> String.split("/") |> hd()

  def link_to_handle(_), do: nil

  def twitter_handle(%Project{twitter_link: nil} = project),
    do: {:error, "Missing twitter link for #{Project.describe(project)}"}

  def twitter_handle(%Project{twitter_link: twitter_link} = project) do
    case link_to_handle(twitter_link) do
      nil -> {:error, "Malformed twitter link for #{Project.describe(project)}"}
      name -> {:ok, name}
    end
  end
end
