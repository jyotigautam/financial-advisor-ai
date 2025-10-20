Postgrex.Types.define(
  FinancialAdvisorAi.PostgresTypes,
  [Pgvector.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
