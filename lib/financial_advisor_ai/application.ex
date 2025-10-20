defmodule FinancialAdvisorAi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FinancialAdvisorAiWeb.Telemetry,
      FinancialAdvisorAi.Repo,
      {DNSCluster, query: Application.get_env(:financial_advisor_ai, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FinancialAdvisorAi.PubSub},
      # Start Oban for background jobs
      {Oban, Application.fetch_env!(:financial_advisor_ai, Oban)},
      # Start to serve requests, typically the last entry
      FinancialAdvisorAiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FinancialAdvisorAi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FinancialAdvisorAiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
