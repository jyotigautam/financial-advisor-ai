defmodule FinancialAdvisorAi.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasks" do
    field :description, :string
    field :status, :string
    field :context, :map
    field :result, :string
    field :error, :string

    belongs_to :user, FinancialAdvisorAi.Accounts.User
    belongs_to :conversation, FinancialAdvisorAi.Chat.Conversation

    timestamps()
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:description, :status, :context, :result, :error, :user_id, :conversation_id])
    |> validate_required([:description, :status, :user_id])
    |> validate_inclusion(:status, ["pending", "in_progress", "waiting_for_response", "completed", "failed"])
  end

  def create_changeset(task, attrs) do
    task
    |> changeset(attrs)
    |> put_change(:status, "pending")
  end

  def update_status_changeset(task, status) when status in ["pending", "in_progress", "waiting_for_response", "completed", "failed"] do
    change(task, status: status)
  end
end
