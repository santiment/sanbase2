defmodule Sanbase.FailedTestFormatter do
  @moduledoc false
  use GenServer

  @failures_dir "_build/test/failures"

  def failures_dir, do: @failures_dir

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
          file = String.replace_leading(test.tags.file, File.cwd!() <> "/", "")
          line = test.tags.line

          # Do not add the reason for now
          _reason = if kind == :exit and is_tuple(error), do: " (#{elem(error, 0)})", else: ""

          test_identifier = "#{file}:#{line}"

          config
          |> Map.update(kind, %{counter: 1, list: [test_identifier]}, fn map ->
            map |> Map.update!(:counter, &(&1 + 1)) |> Map.update!(:list, &[test_identifier | &1])
          end)

        test ->
          IO.warn("Unexpected failed test format. Got: #{inspect(test)}")
          config
      end

    {:noreply, config}
  end

  def handle_cast({:suite_finished, _times_us}, config) do
    print_suite(config)
    write_failures_to_file(config)
    {:noreply, config}
  end

  def handle_cast(_, config) do
    {:noreply, config}
  end

  defp print_suite(config) do
    for kind <- Map.keys(config) do
      if (get_in(config, [kind, :counter]) || 0) > 0 do
        error_tests_message =
          get_in(config, [kind, :list]) |> Enum.map(&(" " <> &1)) |> Enum.join("\n")

        formatted_message =
          IO.ANSI.red() <>
            "\n\n#{String.capitalize(to_string(kind))} tests:\n" <>
            error_tests_message <> "\n" <> IO.ANSI.reset()

        IO.puts(formatted_message)
      end
    end
  end

  defp write_failures_to_file(config) do
    lines =
      for kind <- Map.keys(config),
          (get_in(config, [kind, :counter]) || 0) > 0,
          test_id <- get_in(config, [kind, :list]) do
        "#{kind}\t#{test_id}"
      end

    if lines != [] do
      partition = System.get_env("MIX_TEST_PARTITION") || "0"
      File.mkdir_p!(@failures_dir)

      File.write!(
        Path.join(@failures_dir, "partition_#{partition}.txt"),
        Enum.join(lines, "\n") <> "\n"
      )
    end
  end
end
