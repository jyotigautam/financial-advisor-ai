defmodule FinancialAdvisorAi.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field :role, :string
    field :content, :string
    field :tool_calls, :map
    field :metadata, :map

    belongs_to :conversation, FinancialAdvisorAi.Chat.Conversation

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :tool_calls, :metadata, :conversation_id])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
  end
end
