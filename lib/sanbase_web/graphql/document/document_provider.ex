defmodule SanbaseWeb.Graphql.DocumentProvider do
  @behaviour Absinthe.Plug.DocumentProvider

  @doc false
  @spec pipeline(Absinthe.Plug.Request.t()) :: Absinthe.Pipeline.t()
  def pipeline(%{pipeline: as_configured}) do
    as_configured
    |> Absinthe.Pipeline.replace(
      Absinthe.Phase.Document.Execution.Resolution,
      SanbseWeb.Graphql.Phase.Document.Execution.Resolution
    )
    |> Absinthe.Pipeline.without(Absinthe.Phase.Document.Result)
  end

  @doc false
  @spec process(Absinthe.Plug.Request.Query.t(), Keyword.t()) ::
          Absinthe.DocumentProvider.result()

  def process(%{params: params} = query) do
    {:halt, query}
  end

  def process(%{document: nil} = query, _),
    do: {:cont, query}

  def process(%{document: _} = query, _),
    do: {:halt, query}

  defp process_params(%{"query" => query} = params) do
    IO.inspect(params)
    params
  end
end

defmodule SanbseWeb.Graphql.Phase.Document.Execution.Resolution do
  alias Absinthe.{Blueprint, Phase}

  use Absinthe.Phase

  @spec run(Blueprint.t(), Keyword.t()) :: Phase.result_t()
  def run(bp_root, options \\ []) do
    # Will be fetched from cache - that's what's saved by SanbaseWeb.Graphql.Absinthe.before_send
    result = %{
      data: %{
        "allProjects" => [
          %{"name" => "Bitcoin"},
          %{"name" => "Ethereum"},
          %{"name" => "Ripple"},
          %{"name" => "XRP"},
          %{"name" => "EOS"}
        ]
      }
    }

    {:ok, %{bp_root | result: result}}
  end
end
