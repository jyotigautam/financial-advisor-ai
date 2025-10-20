defmodule FinancialAdvisorAi.Accounts do
  @moduledoc """
  The Accounts context - manages users and authentication
  """

  import Ecto.Query, warn: false
  alias FinancialAdvisorAi.Repo
  alias FinancialAdvisorAi.Accounts.User

  @doc """
  Gets a single user.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Creates a user.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets or creates a demo user for testing
  """
  def get_or_create_demo_user do
    case get_user_by_email("demo@example.com") do
      nil ->
        {:ok, user} = create_user(%{
          email: "demo@example.com",
          name: "Demo User",
          google_id: "demo_google_id"
        })
        user

      user ->
        user
    end
  end

  @doc """
  Creates or updates a user by Google ID.
  """
  def upsert_user_by_google_id(attrs) do
    case Repo.get_by(User, google_id: attrs.google_id) do
      nil ->
        %User{}
        |> User.changeset(attrs)
        |> Repo.insert()

      user ->
        user
        |> User.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Updates user OAuth tokens (Google or HubSpot).
  """
  def update_user_tokens(user_id, token_attrs) do
    user = get_user!(user_id)
    user
    |> User.changeset(token_attrs)
    |> Repo.update()
  end

  @doc """
  Gets user by ID, returns nil if not found.
  """
  def get_user(id) do
    Repo.get(User, id)
  end
end
