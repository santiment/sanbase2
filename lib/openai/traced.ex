defmodule Sanbase.OpenAI.Traced do
  @moduledoc """
  Macro for automatically generating traced versions of OpenAI functions.

  ## Usage

      defmodule MyModule do
        use Sanbase.OpenAI.Traced

        deftraced ask(question) do
          model = Map.get(tracing_opts, :model, @default_model)
          # your implementation that returns {:ok, result} or {:error, reason}
          OpenAI.call(question, model)
        end
      end

  This generates both:
  - `ask/1` - calls with Langfuse tracing (tracing_opts = %{})
  - `ask/2` - calls with Langfuse tracing (question, tracing_opts)

  The variable `tracing_opts` is available within the block via `var!` injection.

  ## Examples

      # With default tracing (tracing_opts = %{})
      MyModule.ask("What is Elixir?")

      # With custom tracing options
      MyModule.ask("What is Elixir?", %{model: "gpt-6-luna", user_id: "user123"})

  ## How It Works

  When you write:

      deftraced ask(question) do
        IO.puts("Model: \#{tracing_opts[:model]}")
        {:ok, "answer"}
      end

  The macro generates 4 functions:

  1. `ask_impl/2` (private) - Your actual implementation with `tracing_opts` injected
  2. `ask_traced/2` (private) - Wraps your impl with tracing instrumentation
  3. `ask/1` (public) - Calls traced version with empty `tracing_opts`
  4. `ask/2` (public) - Calls traced version with custom `tracing_opts`

  The flow is:

      ask(question) -> ask_traced(question, %{})
                    -> Tracing.start()
                    -> ask_impl(question, %{})  # Your code runs here
                    -> Tracing.finalize()
                    -> Returns result to caller

  If tracing fails at any point, your function still executes and returns results.
  Tracing is "best effort" and never blocks the core functionality.
  """

  defmacro __using__(_opts) do
    quote do
      import Sanbase.OpenAI.Traced, only: [deftraced: 2]
      require Logger
    end
  end

  @doc """
  Defines a function and its traced variant.

  The traced version adds an optional `tracing_opts` parameter and wraps
  the original function call with Langfuse tracing instrumentation.

  ## Example

      deftraced ask(question) do
        # Call OpenAI and return {:ok, result} or {:error, reason}
      end

  Generates:
  - `ask/1` - traced version with empty tracing_opts
  - `ask/2` - traced version accepting (question, tracing_opts)
  """
  defmacro deftraced(call, do: block) do
    {name, _meta, args} = call
    arg_names = extract_arg_names(args)
    # credo:disable-for-next-line
    impl_name = String.to_atom("#{name}_impl")
    # credo:disable-for-next-line
    traced_name = String.to_atom("#{name}_traced")

    quote do
      @doc false
      defp unquote(impl_name)(unquote_splicing(args), var!(tracing_opts)) do
        unquote(block)
      end

      @doc false

      defp unquote(traced_name)(unquote_splicing(args), tracing_opts) do
        alias Sanbase.OpenAI.Tracing

        input = unquote(__MODULE__).build_input(unquote(arg_names), tracing_opts)
        model = Map.get(tracing_opts, :model)

        instrumentation_opts =
          tracing_opts
          |> Map.put(:generation_input, input)
          |> Map.put(:trace_input, input)
          |> unquote(__MODULE__).maybe_add_model_metadata(model)
          |> unquote(__MODULE__).maybe_add_model_parameters()

        case Tracing.start(input, instrumentation_opts) do
          {:ok, ctx} ->
            result = unquote(impl_name)(unquote_splicing(arg_names), tracing_opts)
            normalized = unquote(__MODULE__).normalize_result(result)

            try do
              Tracing.finalize(ctx, normalized)
            rescue
              error ->
                Logger.warning("Failed to finalize Langfuse trace: #{inspect(error)}")
            end

            unquote(__MODULE__).unwrap_result(normalized)

          {:error, reason} ->
            if reason != :langfuse_not_configured,
              do: Logger.warning("Langfuse tracing disabled: #{inspect(reason)}")

            unquote(impl_name)(unquote_splicing(arg_names), tracing_opts)
            |> unquote(__MODULE__).normalize_result()
            |> unquote(__MODULE__).unwrap_result()
        end
      end

      def unquote(call) do
        unquote(traced_name)(unquote_splicing(arg_names), %{})
      end

      def unquote(name)(unquote_splicing(args), tracing_opts) do
        unquote(traced_name)(unquote_splicing(arg_names), tracing_opts)
      end
    end
  end

  def build_input([question | _], _opts) when is_binary(question) do
    [%{"role" => "user", "content" => question}]
  end

  def build_input(args, _opts), do: args

  def maybe_add_model_metadata(opts, nil), do: opts

  def maybe_add_model_metadata(opts, model) do
    Map.update(opts, :trace_metadata, %{"model" => model}, &Map.put(&1, "model", model))
  end

  # Parameters that change the model's output, shown on the generation.
  def maybe_add_model_parameters(opts) do
    case Map.take(opts, [:reasoning_effort]) do
      params when params == %{} -> opts
      params -> Map.put_new(opts, :model_parameters, params)
    end
  end

  # The traced block returns either `{:ok, content}` or `{:ok, %{content:,
  # model:, usage:}}`; the latter lets the trace record the served model and
  # token usage.
  def normalize_result({:ok, content}) when is_binary(content) do
    {:ok, %{content: content, model: nil, usage: nil}}
  end

  def normalize_result({:ok, %{content: _} = completion}) do
    {:ok, Map.merge(%{model: nil, usage: nil}, completion)}
  end

  def normalize_result(result), do: result

  # Callers always get `{:ok, content}` back.
  def unwrap_result({:ok, %{content: content}}), do: {:ok, content}
  def unwrap_result(result), do: result

  defp extract_arg_names(nil), do: []

  defp extract_arg_names(args) when is_list(args) do
    Enum.map(args, fn
      {name, meta, context} -> {name, meta, context}
      other -> other
    end)
  end
end
