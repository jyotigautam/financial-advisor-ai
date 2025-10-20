defmodule FinancialAdvisorAi.Workers.EmailSyncWorker do
  @moduledoc """
  Background worker to sync emails from Gmail and create embeddings.
  Runs periodically for each user to keep email data up to date.
  """

  use Oban.Worker,
    queue: :sync,
    max_attempts: 3

  require Logger

  alias FinancialAdvisorAi.Accounts
  alias FinancialAdvisorAi.Integrations.GmailClient
  alias FinancialAdvisorAi.Memory.Embedder
  alias FinancialAdvisorAi.Repo

  @doc """
  Perform email sync for a user.

  Args should contain:
  - user_id: UUID of the user
  - days_back: Number of days to sync (optional, default: 30)
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
    Logger.info("Starting email sync for user #{user_id}")

    user = Accounts.get_user!(user_id)

    if !user.google_access_token do
      Logger.warning("User #{user_id} has no Google token, skipping sync")
      {:ok, :skipped}
    else
      days_back = Map.get(args, "days_back", 30)

      case GmailClient.sync_recent_emails(user, days: days_back) do
        {:ok, emails} ->
          Logger.info("Synced #{length(emails)} emails for user #{user_id}")

          # Create embeddings for new emails
          synced_count = Enum.reduce(emails, 0, fn email, count ->
            case store_email_with_embedding(user.id, email) do
              {:ok, _} -> count + 1
              {:error, reason} ->
                Logger.error("Failed to store email #{email.id}: #{inspect(reason)}")
                count
            end
          end)

          Logger.info("Created #{synced_count} email embeddings for user #{user_id}")

          {:ok, %{emails_synced: length(emails), embeddings_created: synced_count}}

        {:error, reason} ->
          Logger.error("Email sync failed for user #{user_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Enqueue email sync job for a user.
  """
  def enqueue_sync(user_id, opts \\ []) do
    args = %{
      user_id: user_id,
      days_back: Keyword.get(opts, :days_back, 30)
    }

    %{args: args}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Schedule recurring email sync for a user.
  """
  def schedule_recurring_sync(user_id, interval_minutes \\ 30) do
    args = %{user_id: user_id, days_back: 7}

    %{args: args}
    |> __MODULE__.new(schedule_in: {interval_minutes, :minutes})
    |> Oban.insert()
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp store_email_with_embedding(user_id, email) do
    # Check if email already exists
    existing = Repo.get_by(FinancialAdvisorAi.Memory.EmailEmbedding, email_id: email.id)

    if existing do
      {:ok, :already_exists}
    else
      # Create email data structure
      email_data = %{
        id: email.id,
        subject: email.subject || "",
        from: email.from || "",
        to: email.to || "",
        body: email.body || "",
        date: parse_email_date(email.date)
      }

      Embedder.store_email_embedding(user_id, email_data)
    end
  end

  defp parse_email_date(nil), do: DateTime.utc_now()
  defp parse_email_date(date_string) when is_binary(date_string) do
    # Try to parse the date, fallback to current time
    case Timex.parse(date_string, "{RFC1123}") do
      {:ok, datetime} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end
  defp parse_email_date(%DateTime{} = dt), do: dt
end
