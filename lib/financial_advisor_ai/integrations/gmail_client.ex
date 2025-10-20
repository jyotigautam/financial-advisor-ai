defmodule FinancialAdvisorAi.Integrations.GmailClient do
  @moduledoc """
  Gmail API client for reading, sending, and managing emails.
  Automatically handles token refresh when needed.
  """

  require Logger
  alias FinancialAdvisorAi.Accounts.User
  alias FinancialAdvisorAiWeb.AuthController

  @gmail_api_base "https://gmail.googleapis.com/gmail/v1/users/me"

  # ============================================================================
  # EMAIL LISTING AND READING
  # ============================================================================

  @doc """
  List emails with optional filters.

  ## Options
    * `:max_results` - Max number of emails to return (default: 100)
    * `:query` - Gmail search query (e.g., "from:bill@example.com")
    * `:label_ids` - List of label IDs to filter by
    * `:page_token` - Token for pagination

  ## Examples

      iex> GmailClient.list_emails(user)
      {:ok, %{messages: [...], next_page_token: "..."}}

      iex> GmailClient.list_emails(user, query: "from:bill@example.com baseball")
      {:ok, %{messages: [...]}}
  """
  def list_emails(%User{} = user, opts \\ []) do
    with {:ok, user} <- AuthController.ensure_google_token(user) do
      params = build_list_params(opts)
      url = "#{@gmail_api_base}/messages?#{URI.encode_query(params)}"

      headers = [{"Authorization", "Bearer #{user.google_access_token}"}]

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Gmail list_emails error: #{status} - #{inspect(body)}")
          {:error, "Failed to list emails: #{status}"}

        {:error, reason} ->
          Logger.error("Gmail list_emails request failed: #{inspect(reason)}")
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Get full email details by message ID.

  Returns the complete email with headers, body, attachments, etc.

  ## Examples

      iex> GmailClient.get_email(user, "18c8f1234567890a")
      {:ok, %{
        "id" => "18c8f1234567890a",
        "threadId" => "18c8f1234567890a",
        "payload" => %{...},
        "snippet" => "Email preview text..."
      }}
  """
  def get_email(%User{} = user, message_id) do
    with {:ok, user} <- AuthController.ensure_google_token(user) do
      url = "#{@gmail_api_base}/messages/#{message_id}?format=full"
      headers = [{"Authorization", "Bearer #{user.google_access_token}"}]

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to get email: #{status} - #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Get email in simplified format for easier processing.

  Returns a normalized email structure with common fields extracted.

  ## Examples

      iex> GmailClient.get_email_simplified(user, "18c8f1234567890a")
      {:ok, %{
        id: "18c8f1234567890a",
        thread_id: "18c8f1234567890a",
        subject: "Re: Baseball tickets",
        from: "bill@example.com",
        to: "user@example.com",
        date: ~U[2024-01-15 14:30:00Z],
        body: "Email body text...",
        snippet: "Email preview..."
      }}
  """
  def get_email_simplified(%User{} = user, message_id) do
    case get_email(user, message_id) do
      {:ok, raw_email} ->
        simplified = parse_email(raw_email)
        {:ok, simplified}

      error ->
        error
    end
  end

  @doc """
  Sync emails from the last N days and return them in simplified format.

  This is the main function used by background sync jobs.

  ## Examples

      iex> GmailClient.sync_recent_emails(user, days: 7)
      {:ok, [%{id: "...", subject: "...", ...}, ...]}
  """
  def sync_recent_emails(%User{} = user, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    max_results = Keyword.get(opts, :max_results, 500)

    # Calculate date for query
    cutoff_date = DateTime.utc_now() |> DateTime.add(-days, :day)
    date_query = Calendar.strftime(cutoff_date, "%Y/%m/%d")

    query = "after:#{date_query}"

    case list_emails(user, query: query, max_results: max_results) do
      {:ok, %{"messages" => message_list}} when is_list(message_list) ->
        # Fetch full details for each message
        emails = message_list
        |> Enum.map(fn %{"id" => id} ->
          case get_email_simplified(user, id) do
            {:ok, email} -> email
            {:error, _} -> nil
          end
        end)
        |> Enum.filter(& &1 != nil)

        {:ok, emails}

      {:ok, %{}} ->
        # No messages found
        {:ok, []}

      error ->
        error
    end
  end

  # ============================================================================
  # SENDING EMAILS
  # ============================================================================

  @doc """
  Send an email.

  ## Options
    * `:to` - Recipient email (required)
    * `:subject` - Email subject (required)
    * `:body` - Email body (required)
    * `:cc` - CC recipients (optional)
    * `:bcc` - BCC recipients (optional)
    * `:in_reply_to` - Message ID to reply to (optional)
    * `:thread_id` - Thread ID to add to (optional)

  ## Examples

      iex> GmailClient.send_email(user,
        to: "bill@example.com",
        subject: "Re: Baseball tickets",
        body: "I'd love to go! Thanks for the invite."
      )
      {:ok, %{"id" => "18c8f1234567890a", ...}}
  """
  def send_email(%User{} = user, opts) do
    with {:ok, user} <- AuthController.ensure_google_token(user),
         {:ok, raw_message} <- build_email_message(opts) do

      url = "#{@gmail_api_base}/messages/send"
      headers = [
        {"Authorization", "Bearer #{user.google_access_token}"},
        {"Content-Type", "application/json"}
      ]

      body = %{raw: raw_message}
      body = if opts[:thread_id], do: Map.put(body, :threadId, opts[:thread_id]), else: body

      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Gmail send_email error: #{status} - #{inspect(body)}")
          {:error, "Failed to send email: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Reply to an email (maintains thread).

  ## Examples

      iex> GmailClient.reply_to_email(user, original_email_id,
        body: "Thanks for the info!"
      )
      {:ok, %{"id" => "...", ...}}
  """
  def reply_to_email(%User{} = user, original_message_id, opts) do
    case get_email_simplified(user, original_message_id) do
      {:ok, original} ->
        reply_opts = [
          to: original.from,
          subject: add_re_prefix(original.subject),
          body: opts[:body] || "",
          in_reply_to: original.id,
          thread_id: original.thread_id
        ]

        send_email(user, reply_opts)

      error ->
        error
    end
  end

  # ============================================================================
  # EMAIL MODIFICATION
  # ============================================================================

  @doc """
  Modify email labels (mark as read, archive, etc.).

  ## Examples

      iex> GmailClient.modify_labels(user, message_id,
        add_label_ids: ["IMPORTANT"],
        remove_label_ids: ["UNREAD"]
      )
      {:ok, %{"id" => "...", "labelIds" => [...]}}
  """
  def modify_labels(%User{} = user, message_id, opts) do
    with {:ok, user} <- AuthController.ensure_google_token(user) do
      url = "#{@gmail_api_base}/messages/#{message_id}/modify"
      headers = [
        {"Authorization", "Bearer #{user.google_access_token}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        addLabelIds: opts[:add_label_ids] || [],
        removeLabelIds: opts[:remove_label_ids] || []
      }

      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to modify labels: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Mark email as read.
  """
  def mark_as_read(%User{} = user, message_id) do
    modify_labels(user, message_id, remove_label_ids: ["UNREAD"])
  end

  @doc """
  Mark email as unread.
  """
  def mark_as_unread(%User{} = user, message_id) do
    modify_labels(user, message_id, add_label_ids: ["UNREAD"])
  end

  @doc """
  Archive email (remove from inbox).
  """
  def archive_email(%User{} = user, message_id) do
    modify_labels(user, message_id, remove_label_ids: ["INBOX"])
  end

  # ============================================================================
  # SEARCH
  # ============================================================================

  @doc """
  Search emails using Gmail query syntax.

  ## Examples

      iex> GmailClient.search_emails(user, "from:bill@example.com baseball")
      {:ok, [%{subject: "Baseball tickets", ...}, ...]}
  """
  def search_emails(%User{} = user, query, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 50)

    case list_emails(user, query: query, max_results: max_results) do
      {:ok, %{"messages" => message_list}} when is_list(message_list) ->
        emails = message_list
        |> Enum.map(fn %{"id" => id} ->
          case get_email_simplified(user, id) do
            {:ok, email} -> email
            {:error, _} -> nil
          end
        end)
        |> Enum.filter(& &1 != nil)

        {:ok, emails}

      {:ok, %{}} ->
        {:ok, []}

      error ->
        error
    end
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp build_list_params(opts) do
    params = %{}

    params = if opts[:max_results], do: Map.put(params, :maxResults, opts[:max_results]), else: params
    params = if opts[:query], do: Map.put(params, :q, opts[:query]), else: params
    params = if opts[:page_token], do: Map.put(params, :pageToken, opts[:page_token]), else: params

    if opts[:label_ids] do
      Map.put(params, :labelIds, Enum.join(opts[:label_ids], ","))
    else
      params
    end
  end

  defp parse_email(raw_email) do
    payload = raw_email["payload"]
    headers = payload["headers"]

    %{
      id: raw_email["id"],
      thread_id: raw_email["threadId"],
      subject: find_header(headers, "Subject"),
      from: find_header(headers, "From"),
      to: find_header(headers, "To"),
      date: parse_date(find_header(headers, "Date")),
      body: extract_body(payload),
      snippet: raw_email["snippet"],
      label_ids: raw_email["labelIds"] || []
    }
  end

  defp find_header(headers, name) do
    case Enum.find(headers, fn h -> h["name"] == name end) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp extract_body(%{"body" => %{"data" => data}}) when is_binary(data) do
    Base.url_decode64!(data, padding: false)
  end

  defp extract_body(%{"parts" => parts}) when is_list(parts) do
    # Find text/plain or text/html part
    text_part = Enum.find(parts, fn part ->
      part["mimeType"] in ["text/plain", "text/html"]
    end)

    case text_part do
      %{"body" => %{"data" => data}} ->
        Base.url_decode64!(data, padding: false)
      _ ->
        # Try nested parts
        Enum.find_value(parts, "", fn part ->
          if part["parts"], do: extract_body(part), else: nil
        end)
    end
  end

  defp extract_body(_), do: ""

  defp parse_date(nil), do: nil
  defp parse_date(date_string) do
    # Gmail dates are in RFC 2822 format
    # For now, just return the string. Can add proper parsing with Timex if needed
    date_string
  end

  defp build_email_message(opts) do
    to = opts[:to]
    subject = opts[:subject]
    body = opts[:body]

    if !to || !subject || !body do
      {:error, "Missing required fields: to, subject, body"}
    else
      message = """
      To: #{to}
      Subject: #{subject}
      Content-Type: text/plain; charset=utf-8

      #{body}
      """
      |> String.trim()

      # Add optional headers
      message = if opts[:cc], do: "Cc: #{opts[:cc]}\n#{message}", else: message
      message = if opts[:in_reply_to], do: "In-Reply-To: #{opts[:in_reply_to]}\n#{message}", else: message

      # Base64url encode
      encoded = Base.url_encode64(message, padding: false)

      {:ok, encoded}
    end
  end

  defp add_re_prefix(subject) do
    if String.starts_with?(subject, "Re:") do
      subject
    else
      "Re: #{subject}"
    end
  end
end
