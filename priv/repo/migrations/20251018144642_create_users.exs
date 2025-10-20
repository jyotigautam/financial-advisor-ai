defmodule FinancialAdvisorAi.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :email, :string, null: false
      add :name, :string
      add :google_id, :string
      add :google_access_token, :text
      add :google_refresh_token, :text
      add :google_token_expires_at, :utc_datetime
      add :hubspot_access_token, :text
      add :hubspot_refresh_token, :text
      add :hubspot_token_expires_at, :utc_datetime
      add :hubspot_portal_id, :string

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:google_id])
  end
end
