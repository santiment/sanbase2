defmodule SanbaseWeb.GenericAdmin.ObanJob do
  def schema_module, do: Oban.Job
  def resource_name, do: "oban_jobs"

  def resource() do
    %{
      index_fields: [
        :id,
        :state,
        :queue,
        :worker,
        :args,
        :attempt,
        :max_attempts,
        :scheduled_at,
        :completed_at
      ],
      fields_override: %{
        args: %{
          value_modifier: fn job ->
            case Jason.encode(job.args) do
              {:ok, encoded} -> encoded
              {:error, _} -> inspect(job.args)
            end
          end
        },
        errors: %{
          value_modifier: fn job ->
            case job.errors do
              nil -> nil
              errors -> inspect(errors)
            end
          end
        },
        state: %{
          collection: ~w(available scheduled executing completed discarded cancelled retryable),
          type: :select
        },
        worker: %{
          value_modifier: fn job ->
            String.replace(job.worker, "Elixir.", "")
          end
        }
      }
    }
  end
end
