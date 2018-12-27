defmodule SanbaseWeb.Graphql.Resolvers.SocialDataResolver do
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

  def word_context(
        _root,
        %{
          word: word,
          source: source,
          size: size,
          from: from,
          to: to
        },
        _resolution
      ) do
    size = Enum.min([size, 100])
    Sanbase.SocialData.word_context(word, source, size, from, to)
  end
end
