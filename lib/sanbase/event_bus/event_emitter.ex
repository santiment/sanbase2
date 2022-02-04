defmodule Sanbase.EventBus.EventEmitter do
  @moduledoc """
  A behaviour module for implementing Event Bus Emitter

  When the module is used, it exposes a single `emit_event/3` function that
  must be used by the callers. The module that implements the behaviour must
  define the handle_event/3 function.
  """

  defmacro __before_compile__(env) do
    unless Module.defines?(env.module, {:handle_event, 3}) do
      message = """
      function emit_event/3 required by behaviour Sanbase.EventBus.EventEmitter.Behaviour \
      is not implemented (in module #{inspect(env.module)}).
      We will inject a default implementation for now:
          def emit_event(first_arg, _event_type, _args) do
            first_arg
          end
      """

      IO.warn(message, Macro.Env.stacktrace(env))
    end
  end

  defmacro __using__(_opts \\ []) do
    quote location: :keep do
      @behaviour Sanbase.EventBus.EventEmitter.Behaviour

      @before_compile Sanbase.EventBus.EventEmitter

      @callback handle_event(first_arg :: term, event_type :: atom, args :: map) :: term

      require Application

      defmodule ReturnResultError do
        defexception [:message]
      end

      @doc ~s"""
      Emit an event built from the provided arguments.
      If no error, occured, the first argument is returned as-is, so the function
      can be used inside pipelines.
      If changeset param is passed in the args it emits event only if there are actual
      changes in the changeset.
      """
      @spec emit_event(arg :: term, event_type :: atom, args :: map) :: term | no_return
      def emit_event(arg, event_type, %{changeset: changeset} = args) do
        if changeset.changes != %{} do
          emit_event(arg, event_type, Map.delete(args, :changeset))
        else
          arg
        end
      end

      def emit_event(arg, event_type, args) do
        case __MODULE__.handle_event(arg, event_type, args) do
          :ok ->
            maybe_wait(__MODULE__, event_type)
            arg

          error ->
            raise(
              ReturnResultError,
              """
              The handle_event/3 implementation for the event type :#{event_type} \
              returned an error: #{inspect(error)}.
              """
            )
        end
      end

      # In test enviroment, if the test ends before the subscribers successfully
      # handled the event, there will be errors.
      case Application.compile_env(:sanbase, :env) do
        :test ->
          defp maybe_wait(module, event_type, count \\ 5) do
            ets_table = String.to_existing_atom("eb_ew_#{module.topic}")
            # Until a better solution is present, introduce some milliseconds
            # sleep after the event is emitted so there's time for the subcribers
            # to pick it up and do the work.
            Process.sleep(10)

            try do
              events = :ets.tab2list(ets_table)

              if count > 0 and events != [] do
                maybe_wait(module, event_type, count - 1)
              end
            rescue
              _ ->
                :ok
            end
          end

        _ ->
          defp maybe_wait(_module, _event_type, _count \\ 5) do
            :ok
          end
      end
    end
  end
end
