defmodule FinancialAdvisorAi.Repo.Migrations.CreateSyncState do
  use Ecto.Migration

  def change do
    create table(:sync_state, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :service, :string, null: false  # "gmail", "calendar", "hubspot"
      add :last_sync_token, :string  # For incremental sync
      add :last_synced_at, :utc_datetime

      timestamps()
    end

    create unique_index(:sync_state, [:user_id, :service])
  end
end
