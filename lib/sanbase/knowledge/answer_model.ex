defmodule Sanbase.Knowledge.AnswerModel do
  @moduledoc """
  The LLM models that can answer Knowledge questions, and the resolution of a
  selection into the client module + model name the answer pipeline uses.

  Each entry pairs a UI `label` (and stable `key`) with the `client` module
  (`Sanbase.OpenAI.Question` or `Sanbase.OpenRouter.Question`) and the provider
  `model` name. `requires_env` (optional) gates an entry on an env var being set
  and non-empty, so a model only appears when it can actually be called (e.g.
  the OpenRouter-backed model needs `OPENROUTER_API_KEY`).

  `selectable/0` powers the Ask UI dropdown; `options_for/1` turns the chosen
  key into the `:answer_client` / `:answer_model` options `Sanbase.Knowledge`
  threads through; `client/1` and `resolve/1` answer "which client / model will
  actually run", falling back to the app-configured default client when no
  selection is given.
  """

  # The default client used when neither the call options nor app config name
  # one. Overridable at runtime with:
  #     config :sanbase, :knowledge_answer_client, Sanbase.OpenRouter.Question
  @default_client Sanbase.OpenAI.Question

  @models [
    %{
      key: "gpt-5-nano",
      label: "GPT-5 Nano",
      client: Sanbase.OpenAI.Question,
      model: "gpt-5-nano"
    },
    %{
      key: "gpt-5-mini",
      label: "GPT-5 Mini",
      client: Sanbase.OpenAI.Question,
      model: "gpt-5-mini"
    },
    %{
      key: "deepseek-v4-flash",
      label: "DeepSeek V4 Flash",
      client: Sanbase.OpenRouter.Question,
      model: "deepseek/deepseek-v4-flash",
      requires_env: "OPENROUTER_API_KEY"
    }
  ]

  @doc """
  The selectable models (key + label + client + model), filtered to those
  currently usable — an entry with `requires_env` is dropped unless that env var
  is set and non-empty. Evaluated at call time so it reflects the live env.
  """
  @spec selectable() :: [map()]
  def selectable(), do: Enum.filter(@models, &available?/1)

  @doc "The default selectable model's key (the first available entry)."
  @spec default_key() :: String.t()
  def default_key(), do: hd(selectable()).key

  @doc """
  Translate a selectable model `key` into the `:answer_client` / `:answer_model`
  options the answer pipeline reads. An unknown or unavailable key returns `[]`
  so the configured default client/model is used.
  """
  @spec options_for(String.t() | nil) :: keyword()
  def options_for(key) do
    case Enum.find(selectable(), &(&1.key == key)) do
      nil -> []
      choice -> [answer_client: choice.client, answer_model: choice.model]
    end
  end

  @doc """
  The client module that will answer for `options`: the `:answer_client`
  override if given, otherwise the app-configured client, otherwise the default.
  """
  @spec client(keyword()) :: module()
  def client(options) do
    Keyword.get(options, :answer_client) ||
      Application.get_env(:sanbase, :knowledge_answer_client, @default_client)
  end

  @doc """
  The model name the answer step will use for `options`: the `:answer_model`
  override if given, otherwise the resolved client's default. Used to log which
  model produced an answer.
  """
  @spec resolve(keyword()) :: String.t()
  def resolve(options \\ []) do
    Keyword.get(options, :answer_model) || client(options).default_model()
  end

  defp available?(%{requires_env: var}) when is_binary(var) do
    case System.get_env(var) do
      value when is_binary(value) and value != "" -> true
      _ -> false
    end
  end

  defp available?(_), do: true
end
