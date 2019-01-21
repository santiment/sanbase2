defmodule SanbaseWeb.Graphql.Resolvers.SocialDataResolver do
  alias Absinthe.Resolution
  alias SanbaseWeb.Graphql.Helpers.Utils

  @context_words_default_size 10

  def trending_words(
        root,
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

  def word_context(
        %{word: word} = root,
        _args,
        resolution
      ) do
    %{
      source: source,
      from: from,
      to: to
    } = Utils.extract_root_query_args(resolution, "trending_words")

    Sanbase.SocialData.word_context(word, source, @context_words_default_size, from, to)
  end
end
