defmodule Sanbase.Repo.Migrations.FillDocumentTokensPostsColumn do
  use Ecto.Migration

  def up do
    setup()
    Sanbase.Insight.Search.update_all_document_tokens()
  end

  def down do
    :ok
  end

  defp setup() do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()
  end
end
