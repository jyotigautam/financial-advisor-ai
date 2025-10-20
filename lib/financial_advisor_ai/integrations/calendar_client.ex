defmodule FinancialAdvisorAi.Integrations.CalendarClient do
  @moduledoc """
  Google Calendar API client for managing events and calendars.
  Automatically handles token refresh when needed.
  """

  require Logger
  alias FinancialAdvisorAi.Accounts.User
  alias FinancialAdvisorAiWeb.AuthController

  @calendar_api_base "https://www.googleapis.com/calendar/v3"

  # ============================================================================
  # EVENT LISTING
  # ============================================================================

  @doc """
  List calendar events.

  ## Options
    * `:calendar_id` - Calendar ID (default: "primary")
    * `:time_min` - Lower bound for event start time (DateTime)
    * `:time_max` - Upper bound for event start time (DateTime)
    * `:max_results` - Max number of events (default: 250)
    * `:single_events` - Expand recurring events (default: true)
    * `:order_by` - Sort order: "startTime" or "updated"
    * `:q` - Free text search query

  ## Examples

      iex> CalendarClient.list_events(user)
      {:ok, [%{id: "...", summary: "Meeting with Bill", ...}, ...]}

      iex> CalendarClient.list_events(user,
        time_min: ~U[2024-01-01 00:00:00Z],
        time_max: ~U[2024-01-31 23:59:59Z],
        q: "baseball"
      )
      {:ok, [...]}
  """
  def list_events(%User{} = user, opts \\ []) do
    with {:ok, user} <- AuthController.ensure_google_token(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")
      params = build_list_params(opts)

      url = "#{@calendar_api_base}/calendars/#{calendar_id}/events?#{URI.encode_query(params)}"
      headers = [{"Authorization", "Bearer #{user.google_access_token}"}]

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          events = response["items"] || []
          {:ok, Enum.map(events, &parse_event/1)}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Calendar list_events error: #{status} - #{inspect(body)}")
          {:error, "Failed to list events: #{status}"}

        {:error, reason} ->
          Logger.error("Calendar list_events request failed: #{inspect(reason)}")
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Get upcoming events for the next N days.

  ## Examples

      iex> CalendarClient.get_upcoming_events(user, days: 7)
      {:ok, [%{summary: "Lunch meeting", start: ~U[...], ...}, ...]}
  """
  def get_upcoming_events(%User{} = user, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    max_results = Keyword.get(opts, :max_results, 100)

    time_min = DateTime.utc_now()
    time_max = DateTime.add(time_min, days, :day)

    list_events(user,
      time_min: time_min,
      time_max: time_max,
      max_results: max_results,
      order_by: "startTime"
    )
  end

  @doc """
  Get a single event by ID.

  ## Examples

      iex> CalendarClient.get_event(user, "event_id_123")
      {:ok, %{id: "event_id_123", summary: "Meeting", ...}}
  """
  def get_event(%User{} = user, event_id, opts \\ []) do
    with {:ok, user} <- AuthController.ensure_google_token(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")
      url = "#{@calendar_api_base}/calendars/#{calendar_id}/events/#{event_id}"
      headers = [{"Authorization", "Bearer #{user.google_access_token}"}]

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, parse_event(response)}

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to get event: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  # ============================================================================
  # EVENT CREATION
  # ============================================================================

  @doc """
  Create a calendar event.

  ## Options
    * `:summary` - Event title (required)
    * `:description` - Event description
    * `:location` - Event location
    * `:start` - Start time as DateTime (required)
    * `:end` - End time as DateTime (required)
    * `:attendees` - List of attendee emails
    * `:calendar_id` - Calendar to add to (default: "primary")
    * `:send_notifications` - Send email notifications (default: true)

  ## Examples

      iex> CalendarClient.create_event(user,
        summary: "Lunch with Bill",
        start: ~U[2024-01-15 12:00:00Z],
        end: ~U[2024-01-15 13:00:00Z],
        attendees: ["bill@example.com"]
      )
      {:ok, %{id: "...", summary: "Lunch with Bill", ...}}
  """
  def create_event(%User{} = user, opts) do
    with {:ok, user} <- AuthController.ensure_google_token(user),
         {:ok, event_body} <- build_event_body(opts) do

      calendar_id = Keyword.get(opts, :calendar_id, "primary")
      send_notifications = Keyword.get(opts, :send_notifications, true)

      url = "#{@calendar_api_base}/calendars/#{calendar_id}/events?sendNotifications=#{send_notifications}"
      headers = [
        {"Authorization", "Bearer #{user.google_access_token}"},
        {"Content-Type", "application/json"}
      ]

      case Req.post(url, json: event_body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, parse_event(response)}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Calendar create_event error: #{status} - #{inspect(body)}")
          {:error, "Failed to create event: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  # ============================================================================
  # EVENT MODIFICATION
  # ============================================================================

  @doc """
  Update an existing event.

  ## Examples

      iex> CalendarClient.update_event(user, "event_id_123",
        summary: "Updated meeting title",
        start: ~U[2024-01-15 14:00:00Z]
      )
      {:ok, %{id: "event_id_123", summary: "Updated meeting title", ...}}
  """
  def update_event(%User{} = user, event_id, opts) do
    with {:ok, user} <- AuthController.ensure_google_token(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")

      # First, get the existing event
      case get_event(user, event_id, calendar_id: calendar_id) do
        {:ok, existing_event} ->
          # Merge updates with existing event
          updated_body = merge_event_updates(existing_event, opts)

          url = "#{@calendar_api_base}/calendars/#{calendar_id}/events/#{event_id}"
          headers = [
            {"Authorization", "Bearer #{user.google_access_token}"},
            {"Content-Type", "application/json"}
          ]

          case Req.put(url, json: updated_body, headers: headers) do
            {:ok, %{status: 200, body: response}} ->
              {:ok, parse_event(response)}

            {:ok, %{status: status, body: body}} ->
              {:error, "Failed to update event: #{status}"}

            {:error, reason} ->
              {:error, "Request failed: #{inspect(reason)}"}
          end

        error ->
          error
      end
    end
  end

  @doc """
  Delete a calendar event.

  ## Examples

      iex> CalendarClient.delete_event(user, "event_id_123")
      :ok
  """
  def delete_event(%User{} = user, event_id, opts \\ []) do
    with {:ok, user} <- AuthController.ensure_google_token(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")
      send_notifications = Keyword.get(opts, :send_notifications, true)

      url = "#{@calendar_api_base}/calendars/#{calendar_id}/events/#{event_id}?sendNotifications=#{send_notifications}"
      headers = [{"Authorization", "Bearer #{user.google_access_token}"}]

      case Req.delete(url, headers: headers) do
        {:ok, %{status: 204}} ->
          :ok

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to delete event: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  # ============================================================================
  # SEARCH
  # ============================================================================

  @doc """
  Search for events matching a query.

  ## Examples

      iex> CalendarClient.search_events(user, "baseball")
      {:ok, [%{summary: "Baseball game tickets", ...}, ...]}

      iex> CalendarClient.search_events(user, "Bill", days: 30)
      {:ok, [...]}
  """
  def search_events(%User{} = user, query, opts \\ []) do
    days = Keyword.get(opts, :days, 365)
    time_min = DateTime.utc_now()
    time_max = DateTime.add(time_min, days, :day)

    list_events(user,
      q: query,
      time_min: time_min,
      time_max: time_max,
      max_results: Keyword.get(opts, :max_results, 50)
    )
  end

  @doc """
  Find events with specific attendees.

  ## Examples

      iex> CalendarClient.find_events_with_attendee(user, "bill@example.com", days: 30)
      {:ok, [%{summary: "Meeting with Bill", attendees: [...], ...}, ...]}
  """
  def find_events_with_attendee(%User{} = user, attendee_email, opts \\ []) do
    days = Keyword.get(opts, :days, 365)

    case get_upcoming_events(user, days: days, max_results: 500) do
      {:ok, events} ->
        filtered = Enum.filter(events, fn event ->
          attendees = event[:attendees] || []
          Enum.any?(attendees, fn a -> a[:email] == attendee_email end)
        end)

        {:ok, filtered}

      error ->
        error
    end
  end

  # ============================================================================
  # AVAILABILITY
  # ============================================================================

  @doc """
  Find free time slots in the calendar.

  Returns time slots where there are no events scheduled.

  ## Examples

      iex> CalendarClient.find_free_slots(user,
        start_date: ~U[2024-01-15 00:00:00Z],
        end_date: ~U[2024-01-15 23:59:59Z],
        slot_duration_minutes: 60
      )
      {:ok, [
        %{start: ~U[2024-01-15 09:00:00Z], end: ~U[2024-01-15 10:00:00Z]},
        %{start: ~U[2024-01-15 14:00:00Z], end: ~U[2024-01-15 15:00:00Z]}
      ]}
  """
  def find_free_slots(%User{} = user, opts) do
    start_date = Keyword.fetch!(opts, :start_date)
    end_date = Keyword.fetch!(opts, :end_date)

    case list_events(user, time_min: start_date, time_max: end_date) do
      {:ok, events} ->
        # Sort events by start time
        sorted_events = Enum.sort_by(events, fn e -> e[:start] end, DateTime)

        # Find gaps between events
        free_slots = find_gaps_between_events(sorted_events, start_date, end_date)

        {:ok, free_slots}

      error ->
        error
    end
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp build_list_params(opts) do
    params = %{
      singleEvents: Keyword.get(opts, :single_events, true),
      maxResults: Keyword.get(opts, :max_results, 250)
    }

    params = if opts[:time_min], do: Map.put(params, :timeMin, DateTime.to_iso8601(opts[:time_min])), else: params
    params = if opts[:time_max], do: Map.put(params, :timeMax, DateTime.to_iso8601(opts[:time_max])), else: params
    params = if opts[:order_by], do: Map.put(params, :orderBy, opts[:order_by]), else: params
    params = if opts[:q], do: Map.put(params, :q, opts[:q]), else: params

    params
  end

  defp parse_event(event) do
    %{
      id: event["id"],
      summary: event["summary"],
      description: event["description"],
      location: event["location"],
      start: parse_datetime(event["start"]),
      end: parse_datetime(event["end"]),
      attendees: parse_attendees(event["attendees"]),
      organizer: event["organizer"],
      status: event["status"],
      html_link: event["htmlLink"],
      raw: event
    }
  end

  defp parse_datetime(%{"dateTime" => dt_string}) do
    case DateTime.from_iso8601(dt_string) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
  defp parse_datetime(%{"date" => date_string}) do
    # All-day event - just store the date string
    date_string
  end
  defp parse_datetime(_), do: nil

  defp parse_attendees(nil), do: []
  defp parse_attendees(attendees) when is_list(attendees) do
    Enum.map(attendees, fn a ->
      %{
        email: a["email"],
        display_name: a["displayName"],
        response_status: a["responseStatus"],
        organizer: a["organizer"] || false
      }
    end)
  end

  defp build_event_body(opts) do
    summary = opts[:summary]
    start_time = opts[:start]
    end_time = opts[:end]

    if !summary || !start_time || !end_time do
      {:error, "Missing required fields: summary, start, end"}
    else
      event = %{
        summary: summary,
        start: %{dateTime: DateTime.to_iso8601(start_time)},
        end: %{dateTime: DateTime.to_iso8601(end_time)}
      }

      event = if opts[:description], do: Map.put(event, :description, opts[:description]), else: event
      event = if opts[:location], do: Map.put(event, :location, opts[:location]), else: event

      event = if opts[:attendees] do
        attendees = Enum.map(opts[:attendees], fn email -> %{email: email} end)
        Map.put(event, :attendees, attendees)
      else
        event
      end

      {:ok, event}
    end
  end

  defp merge_event_updates(existing_event, updates) do
    base = existing_event[:raw]

    base = if updates[:summary], do: Map.put(base, "summary", updates[:summary]), else: base
    base = if updates[:description], do: Map.put(base, "description", updates[:description]), else: base
    base = if updates[:location], do: Map.put(base, "location", updates[:location]), else: base

    base = if updates[:start] do
      Map.put(base, "start", %{"dateTime" => DateTime.to_iso8601(updates[:start])})
    else
      base
    end

    base = if updates[:end] do
      Map.put(base, "end", %{"dateTime" => DateTime.to_iso8601(updates[:end])})
    else
      base
    end

    base
  end

  defp find_gaps_between_events(events, start_boundary, end_boundary) do
    # This is a simplified version - could be enhanced with business hours, minimum slot duration, etc.
    gaps = []

    # Add gap before first event
    gaps = case List.first(events) do
      %{start: first_start} when is_struct(first_start, DateTime) ->
        if DateTime.compare(start_boundary, first_start) == :lt do
          [%{start: start_boundary, end: first_start} | gaps]
        else
          gaps
        end
      _ -> gaps
    end

    # Add gaps between events
    gaps = events
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(gaps, fn [event1, event2], acc ->
      if is_struct(event1[:end], DateTime) && is_struct(event2[:start], DateTime) do
        if DateTime.compare(event1[:end], event2[:start]) == :lt do
          [%{start: event1[:end], end: event2[:start]} | acc]
        else
          acc
        end
      else
        acc
      end
    end)

    # Add gap after last event
    gaps = case List.last(events) do
      %{end: last_end} when is_struct(last_end, DateTime) ->
        if DateTime.compare(last_end, end_boundary) == :lt do
          [%{start: last_end, end: end_boundary} | gaps]
        else
          gaps
        end
      _ -> gaps
    end

    Enum.reverse(gaps)
  end
end
