defmodule Mix.Tasks.ParallelTest do
  use Mix.Task

  @shortdoc "Run the tests in parallel"

  @moduledoc """
  Runs the tests in parallel
  """

  @switches [
    concurrency: :integer,
    slowest: :integer,
    silence_warnings: :boolean
  ]

  # @ets_table :__logs_colector_ets_table__

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches)

    concurrency = Keyword.get(opts, :concurrency, 4)
    slowest = Keyword.get(opts, :slowest, 10)
    silence_warnings = Keyword.get(opts, :silence_warnings, false)

    # _ = :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true])

    before_start_time = DateTime.utc_now()

    callback = fn _partition, output ->
      # logs = partition_logs(partition)

      # true = :ets.insert(@ets_table, {partition, [output | logs]})

      case String.starts_with?(output, "warning:") && silence_warnings do
        false -> IO.puts(output)
        true -> :ok
      end
    end

    exit_codes =
      1..concurrency
      |> Enum.map(fn partition ->
        Task.async(fn ->
          Mix.Shell.cmd(
            """
            mix test --partitions #{concurrency} --formatter Sanbase.FailedTestFormatter --formatter ExUnit.CLIFormatter --slowest #{
              slowest
            }
            """,
            [
              env: [
                {"PORT", "400#{partition}"},
                {"MIX_TEST_PARTITION", "#{partition}"}
              ]
            ],
            &callback.(partition, &1)
          )
        end)
      end)
      |> Enum.map(&Task.await(&1, :infinity))

    exit_code =
      case Enum.all?(exit_codes, &(&1 == 0)) do
        true -> :ok
        false -> System.at_exit(fn _ -> exit({:shutdown, 1}) end)
      end

    # logs_per_partition = logs_per_partition(concurrency)
    # slowest = slowest(logs_per_partition, slowest)

    # IO.puts("Top #{slowest} slowest tests:\n\n")
    # slowest |> Enum.each(&IO.puts/1)

    IO.puts(
      "\n\nTests took: #{DateTime.diff(DateTime.utc_now(), before_start_time, :second)} seconds"
    )

    exit_code
  end

  # defp logs_per_partition(concurrency) do
  #   1..concurrency
  #   |> Enum.map(fn partition ->
  #     logs = partition_logs(partition) |> Enum.reverse()
  #     {partition, logs}
  #   end)
  # end

  # defp slowest(logs_per_partition, slowest) do
  #   logs_per_partition
  #   |> Enum.flat_map(fn {_partition, logs} ->
  #     logs
  #     |> Enum.drop_while(fn line -> not (line =~ "Top #{slowest} slowest") end)
  #     |> Enum.drop(1)
  #     |> Enum.take(1)
  #     |> hd()
  #     |> String.split("\n")
  #     |> Enum.reject(&(&1 == ""))
  #     |> Enum.map(fn line ->
  #       time =
  #         line
  #         |> String.split("(")
  #         |> Enum.at(-2)
  #         |> Float.parse()
  #         |> case do
  #           {float, _} when is_float(float) -> float
  #           _ -> 0.0
  #         end

  #       {time, line}
  #     end)
  #   end)
  #   |> Enum.sort_by(fn {time, _} -> time end, :desc)
  #   |> Enum.take(slowest)
  #   |> Enum.map(fn {_time, line} -> line end)
  # end

  # defp partition_logs(partition) do
  #   case :ets.lookup(@ets_table, partition) do
  #     [{^partition, logs}] -> logs
  #     [] -> []
  #   end
  # end
end
