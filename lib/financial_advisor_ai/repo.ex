defmodule FinancialAdvisorAi.Repo do
  use Ecto.Repo,
    otp_app: :financial_advisor_ai,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_type, config) do
    # Configure pgvector types
    {:ok, Keyword.put(config, :types, Pgvector.Ecto.Types)}
  end
end
