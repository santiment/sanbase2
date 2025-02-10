defmodule Sanbase.FailedTestFormatter do
  @moduledoc false
  use GenServer

  ## Callbacks

  def init(_opts) do
    {:ok,
     %{
       :error => %{list: [], counter: 0},
       :invalid => %{list: [], counter: 0}
     }}
  end

  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, _}} = test}, config) do
    config =
      case test do
        %ExUnit.Test{state: {:failed, [{kind, error, _stacktrace}]}} = test
        when kind in [:error, :invalid, :exit] ->
          # Add a leading dot so the file:line string can be copy-pasted in the
          # terminal to directly execute it
          file = String.replace_leading(test.tags.file, File.cwd!() <> "/", "")
          line = test.tags.line

          # In case of :exit, the error tuple can contain more info, like :timeout, etc.
          # In case of :error, the error is not a tuple, but a struct
          reason = if kind == :exit and is_tuple(error), do: " (#{elem(error, 0)})", else: ""

          test_identifier = "#{file}:#{line}#{reason}"

          Map.update(config, kind, %{counter: 1, list: [test_identifier]}, fn map ->
            map |> Map.update!(:counter, &(&1 + 1)) |> Map.update!(:list, &[test_identifier | &1])
          end)

        # TODO: Support ExUnit.MultiError
        test ->
          IO.warn("Unexpected failed test format. Got: #{inspect(test)}")
          config
      end

    {:noreply, config}
  end

  def handle_cast({:suite_finished, _times_us}, config) do
    print_suite(config)
    {:noreply, config}
  end

  def handle_cast(_, config) do
    {:noreply, config}
  end

  defp print_suite(config) do
    for kind <- Map.keys(config) do
      if (get_in(config, [kind, :counter]) || 0) > 0 do
        # All tests that failed an assert will have `kind = :error`
        error_tests_message =
          config |> get_in([kind, :list]) |> Enum.map_join("\n", &(" " <> &1))

        formatted_message =
          IO.ANSI.red() <>
            "\n\n#{String.capitalize(to_string(kind))} tests:\n" <>
            error_tests_message <> "\n" <> IO.ANSI.reset()

        IO.puts(formatted_message)
      end
    end
  end
end
