defmodule FinancialAdvisorAi.AI.IntentParser do
  @moduledoc """
  Simple keyword-based intent parser for Gemini.
  Detects user intent and extracts parameters for tool calling.
  """

  alias FinancialAdvisorAi.AI.ToolRegistry

  @doc """
  Parse user message and detect intent with parameters.

  Returns {:tool, tool_name, args} if a tool should be called,
  or {:chat, message} if it's a regular chat message.
  """
  def parse_intent(message) when is_binary(message) do
    message_lower = String.downcase(message)

    cond do
      # Calendar - List upcoming events
      matches_pattern?(message_lower, ["upcoming", "meeting"]) or
      matches_pattern?(message_lower, ["what", "meeting"]) or
      matches_pattern?(message_lower, ["show", "calendar"]) or
      matches_pattern?(message_lower, ["list", "event"]) ->
        days = extract_number(message, default: 7)
        {:tool, "list_calendar_events", %{"days" => days}}

      # Calendar - Schedule/Create event
      matches_pattern?(message_lower, ["schedule", "event"]) or
      matches_pattern?(message_lower, ["schedule", "meeting"]) or
      matches_pattern?(message_lower, ["create", "event"]) or
      matches_pattern?(message_lower, ["book", "meeting"]) ->
        case extract_event_details(message) do
          {:ok, details} -> {:tool, "create_calendar_event", details}
          :error -> {:clarify, "I need more details to schedule the event. Please provide: who (email), when (date/time), and what (subject/title)."}
        end

      # Email - Send
      matches_pattern?(message_lower, ["send", "email"]) or
      matches_pattern?(message_lower, ["email", "to"]) or
      matches_pattern?(message_lower, ["write", "email"]) ->
        case extract_email_details(message) do
          {:ok, details} -> {:tool, "send_email", details}
          :error -> {:clarify, "I need the recipient's email, subject, and message body to send an email."}
        end

      # HubSpot - Get contact
      matches_pattern?(message_lower, ["find", "contact"]) or
      matches_pattern?(message_lower, ["look up", "contact"]) or
      matches_pattern?(message_lower, ["hubspot", "contact"]) ->
        case extract_email_from_text(message) do
          {:ok, email} -> {:tool, "get_hubspot_contact", %{"email" => email}}
          :error -> {:clarify, "Please provide the contact's email address."}
        end

      # Default - regular chat (will use RAG if applicable)
      true ->
        {:chat, message}
    end
  end

  # Helper: Check if message contains all words in pattern
  defp matches_pattern?(message, words) do
    Enum.all?(words, fn word -> String.contains?(message, word) end)
  end

  # Extract event details from natural language
  defp extract_event_details(message) do
    with {:ok, email} <- extract_email_from_text(message),
         {:ok, datetime} <- extract_datetime(message),
         summary <- extract_summary(message) do

      end_time = DateTime.add(datetime, 3600, :second)  # Default 1 hour duration

      {:ok, %{
        "summary" => summary,
        "start_time" => DateTime.to_iso8601(datetime),
        "end_time" => DateTime.to_iso8601(end_time),
        "attendees" => [email]
      }}
    else
      _ -> :error
    end
  end

  # Extract email details
  defp extract_email_details(message) do
    case extract_email_from_text(message) do
      {:ok, to_email} ->
        subject = extract_subject(message)
        body = extract_body(message) || extract_message_content(message)

        {:ok, %{
          "to" => to_email,
          "subject" => subject || "Message from AI Assistant",
          "body" => body
        }}

      :error ->
        :error
    end
  end

  # Extract email address from text
  defp extract_email_from_text(text) do
    # Simple email regex
    case Regex.run(~r/([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/, text) do
      [email | _] -> {:ok, email}
      nil -> :error
    end
  end

  # Extract datetime from natural language
  defp extract_datetime(text) do
    text_lower = String.downcase(text)
    now = DateTime.utc_now()

    cond do
      # "tomorrow at 2pm", "tomorrow 2 pm"
      String.contains?(text_lower, "tomorrow") ->
        time = extract_time(text_lower, default_hour: 14)
        tomorrow = DateTime.add(now, 86400, :second)
        {:ok, set_time(tomorrow, time)}

      # "today at 3pm"
      String.contains?(text_lower, "today") ->
        time = extract_time(text_lower, default_hour: 14)
        {:ok, set_time(now, time)}

      # "on 20th Oct 12 pm", "on Oct 20 at 12pm"
      date_match = Regex.run(~r/on\s+(\d{1,2})(?:st|nd|rd|th)?\s+(\w+)/, text_lower) ->
        [_, day_str, month_str] = date_match
        time = extract_time(text_lower, default_hour: 12)

        day = String.to_integer(day_str)
        month = parse_month(month_str)
        year = now.year

        case Date.new(year, month, day) do
          {:ok, date} ->
            datetime = DateTime.new!(date, Time.new!(time.hour, time.minute, 0))
            {:ok, datetime}
          _ -> :error
        end

      # Default - 1 hour from now
      true ->
        {:ok, DateTime.add(now, 3600, :second)}
    end
  end

  # Extract time from text (returns %{hour: 14, minute: 0})
  defp extract_time(text, opts \\ []) do
    default_hour = Keyword.get(opts, :default_hour, 14)

    cond do
      # "2pm", "2 pm", "14:00"
      match = Regex.run(~r/(\d{1,2})\s*(?::(\d{2}))?\s*(am|pm)?/i, text) ->
        [_, hour_str | rest] = match
        hour = String.to_integer(hour_str)
        minute = case rest do
          [min_str, _] when min_str != "" -> String.to_integer(min_str)
          _ -> 0
        end

        meridiem = List.last(rest)
        hour = adjust_hour_for_meridiem(hour, meridiem)

        %{hour: hour, minute: minute}

      true ->
        %{hour: default_hour, minute: 0}
    end
  end

  defp adjust_hour_for_meridiem(hour, nil), do: hour
  defp adjust_hour_for_meridiem(hour, ""), do: hour
  defp adjust_hour_for_meridiem(hour, meridiem) when is_binary(meridiem) do
    case String.downcase(meridiem) do
      "pm" when hour < 12 -> hour + 12
      "am" when hour == 12 -> 0
      _ -> hour
    end
  end

  defp set_time(datetime, %{hour: hour, minute: minute}) do
    date = DateTime.to_date(datetime)
    time = Time.new!(hour, minute, 0)
    DateTime.new!(date, time)
  end

  # Parse month name to number
  defp parse_month(month_str) do
    month_str = String.downcase(month_str)

    months = %{
      "jan" => 1, "january" => 1,
      "feb" => 2, "february" => 2,
      "mar" => 3, "march" => 3,
      "apr" => 4, "april" => 4,
      "may" => 5,
      "jun" => 6, "june" => 6,
      "jul" => 7, "july" => 7,
      "aug" => 8, "august" => 8,
      "sep" => 9, "september" => 9,
      "oct" => 10, "october" => 10,
      "nov" => 11, "november" => 11,
      "dec" => 12, "december" => 12
    }

    months[month_str] || 1
  end

  # Extract number from text
  defp extract_number(text, opts \\ []) do
    default = Keyword.get(opts, :default, 1)

    case Regex.run(~r/(\d+)/, text) do
      [_, num_str] -> String.to_integer(num_str)
      nil -> default
    end
  end

  # Extract meeting summary/title
  defp extract_summary(text) do
    cond do
      String.contains?(text, "for ") ->
        case String.split(text, "for ", parts: 2) do
          [_, summary] ->
            summary
            |> String.split(~r/\s+on\s+|\s+at\s+|\s+with\s+/, parts: 2)
            |> List.first()
            |> String.trim()
          _ -> "Meeting"
        end

      true -> "Meeting"
    end
  end

  # Extract email subject
  defp extract_subject(text) do
    cond do
      String.contains?(text, "subject:") ->
        text
        |> String.split("subject:", parts: 2)
        |> List.last()
        |> String.split("\n", parts: 2)
        |> List.first()
        |> String.trim()

      true -> nil
    end
  end

  # Extract email body
  defp extract_body(text) do
    cond do
      String.contains?(text, "body:") ->
        text
        |> String.split("body:", parts: 2)
        |> List.last()
        |> String.trim()

      String.contains?(text, "saying ") ->
        text
        |> String.split("saying ", parts: 2)
        |> List.last()
        |> String.trim()

      true -> nil
    end
  end

  defp extract_message_content(text) do
    # Try to extract content after "saying"
    cond do
      String.contains?(text, "saying ") ->
        text
        |> String.split("saying ", parts: 2)
        |> List.last()
        |> String.trim()

      true ->
        # Fallback: remove command part
        text
        |> String.replace(~r/(send|email|write).+(to|@)\S+/i, "")
        |> String.trim()
    end
  end
end
