defmodule SanbaseWeb.Graphql.Resolvers.SocialDataResolver do
  require Sanbase.Utils.Config, as: Config

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
    size = Enum.min([size, 100])
    Sanbase.SocialData.trending_words(source, size, hour, from, to)
  end
end
