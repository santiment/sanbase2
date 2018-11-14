defmodule SanbaseWeb.Graphql.Resolvers.SocialDataResolver do
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.SocialData.SocialData

  def trending_words(
        _root,
        %{
          source: source,
          size: size,
          hour: hour,
          from: from,
          to: to
        },
        _resolution
      ) do
    SocialData.trending_words(source, size, hour, from, to)
  end
end
