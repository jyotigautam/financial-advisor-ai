defmodule FinancialAdvisorAi.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, type: :uuid, on_delete: :nilify_all)
      add :description, :text, null: false
      add :status, :string, null: false  # "pending", "in_progress", "waiting_for_response", "completed", "failed"
      add :context, :jsonb  # Store task context (emails sent, responses received, etc.)
      add :result, :text  # Final result of the task
      add :error, :text  # Error message if failed

      timestamps()
    end

    create index(:tasks, [:user_id])
    create index(:tasks, [:user_id, :status])
    create index(:tasks, [:conversation_id])
  end
end
