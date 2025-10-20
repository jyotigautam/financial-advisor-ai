defmodule FinancialAdvisorAi.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversations" do
    field :title, :string
    field :archived, :boolean, default: false

    belongs_to :user, FinancialAdvisorAi.Accounts.User
    has_many :messages, FinancialAdvisorAi.Chat.Message

    timestamps()
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :archived, :user_id])
    |> validate_required([:user_id])
  end
end
