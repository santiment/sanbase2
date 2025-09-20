defmodule Sanbase.AI.Embedding.Behavior do
  @moduledoc """
  Behavior for the OpenAI Embedding module to facilitate mocking in tests.
  """

  @callback generate_embeddings([String.t()], non_neg_integer()) ::
              {:ok, [[float()]]} | {:error, String.t()}
end
