defmodule FinancialAdvisorAi.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :google_id, :string
    field :google_access_token, :string
    field :google_refresh_token, :string
    field :google_token_expires_at, :utc_datetime
    field :hubspot_access_token, :string
    field :hubspot_refresh_token, :string
    field :hubspot_token_expires_at, :utc_datetime
    field :hubspot_portal_id, :string

    has_many :conversations, FinancialAdvisorAi.Chat.Conversation
    has_many :tasks, FinancialAdvisorAi.Tasks.Task
    has_many :ongoing_instructions, FinancialAdvisorAi.Instructions.OngoingInstruction
    has_many :email_embeddings, FinancialAdvisorAi.Memory.EmailEmbedding
    has_many :contact_embeddings, FinancialAdvisorAi.Memory.ContactEmbedding

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :name,
      :google_id,
      :google_access_token,
      :google_refresh_token,
      :google_token_expires_at,
      :hubspot_access_token,
      :hubspot_refresh_token,
      :hubspot_token_expires_at,
      :hubspot_portal_id
    ])
    |> validate_required([:email])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
    |> unique_constraint(:google_id)
  end

  @doc """
  Creates a changeset for OAuth registration
  """
  def oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :google_id])
    |> validate_required([:email, :google_id])
    |> unique_constraint(:email)
    |> unique_constraint(:google_id)
  end

  @doc """
  Updates Google OAuth tokens
  """
  def google_token_changeset(user, attrs) do
    user
    |> cast(attrs, [:google_access_token, :google_refresh_token, :google_token_expires_at])
    |> validate_required([:google_access_token])
  end

  @doc """
  Updates HubSpot OAuth tokens
  """
  def hubspot_token_changeset(user, attrs) do
    user
    |> cast(attrs, [:hubspot_access_token, :hubspot_refresh_token, :hubspot_token_expires_at, :hubspot_portal_id])
    |> validate_required([:hubspot_access_token])
  end

  @doc """
  Checks if Google token is expired
  """
  def google_token_expired?(%__MODULE__{google_token_expires_at: nil}), do: true
  def google_token_expired?(%__MODULE__{google_token_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if HubSpot token is expired
  """
  def hubspot_token_expired?(%__MODULE__{hubspot_token_expires_at: nil}), do: true
  def hubspot_token_expired?(%__MODULE__{hubspot_token_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
