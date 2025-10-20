defmodule FinancialAdvisorAiWeb.Router do
  use FinancialAdvisorAiWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FinancialAdvisorAiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # OAuth pipeline
  pipeline :auth do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_secure_browser_headers
  end

  scope "/", FinancialAdvisorAiWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/chat", ChatLive
    live "/chat/:id", ChatLive
  end

  # OAuth routes
  scope "/auth", FinancialAdvisorAiWeb do
    pipe_through :auth

    # Google OAuth (via Ueberauth)
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/:provider/callback", AuthController, :callback

    # HubSpot OAuth (custom implementation)
    get "/hubspot/authorize", AuthController, :hubspot_authorize

    # Sign out
    get "/signout", AuthController, :signout
  end

  # Webhook routes (API endpoints)
  scope "/webhooks", FinancialAdvisorAiWeb do
    pipe_through :api

    # Gmail push notifications
    post "/gmail", WebhookController, :gmail_webhook

    # Google Calendar push notifications
    post "/calendar", WebhookController, :calendar_webhook

    # HubSpot webhooks
    post "/hubspot", WebhookController, :hubspot_webhook
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:financial_advisor_ai, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FinancialAdvisorAiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
