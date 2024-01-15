defmodule Sanbase.Project.TwitterData do
  alias Sanbase.Project

  def link_to_handle("https://twitter.com/" <> twitter_name),
    do: String.split(twitter_name, "/") |> hd()

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
