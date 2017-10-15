defmodule SanbaseWeb.Router do
  use SanbaseWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :nextjs do
    plug :accepts, ["html"]
    plug :put_secure_browser_headers
  end

  scope "/api", SanbaseWeb do
    pipe_through :api

    resources "/items", ItemController, only: [:index]
    resources "/cashflow", CashflowController, only: [:index]
  end

  scope "/" do
    pipe_through [:nextjs]

    get "/*path", ReverseProxy, upstream: [Application.fetch_env!(:sanbase, :node_server)]
  end
end
