defmodule Sanbase.AI.Embedding do
  @module Sanbase.AI.Embedding.OpenAI

  def generate_embeddings(texts, size) do
    @module.generate_embeddings(texts, size)
  end
end
