defmodule FinancialAdvisorAi.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :title, :string
      add :archived, :boolean, default: false

      timestamps()
    end

    create index(:conversations, [:user_id])
    create index(:conversations, [:user_id, :archived])
  end
end
