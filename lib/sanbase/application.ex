defmodule Sanbase.Application do
  require Logger

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(type, args) do
    case System.get_env("CONTAINER_TYPE") || "web" do
      "web" ->
        Logger.info("Starting WEB Sanbase.")
        Sanbase.Application.WebSupervisor.start(type, args)

      "scrapers" ->
        Logger.info("Starting Scrapers Sanbase.")
        Sanbase.Application.ScrapersSupervisor.start(type, args)

      "workers" ->
        Logger.info("Starting Workers Sanbase.")
        Sanbase.Application.WorkersSupervisor.start(type, args)
    end
  end
end
