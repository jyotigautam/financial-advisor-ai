defmodule FinancialAdvisorAi.AI.ToolRegistry do
  @moduledoc """
  Registry of all available tools that the AI agent can call.
  Each tool has a schema (for LLM) and an executor function.
  """

  alias FinancialAdvisorAi.Integrations.{GmailClient, CalendarClient, HubspotClient}
  alias FinancialAdvisorAi.Memory.Search
  alias FinancialAdvisorAi.Accounts

  @doc """
  Get all available tools with their schemas for the LLM.

  Returns a list of tool definitions that can be passed to the LLM.
  """
  def get_all_tools do
    [
      search_emails_tool(),
      search_contacts_tool(),
      send_email_tool(),
      create_calendar_event_tool(),
      list_calendar_events_tool(),
      search_calendar_events_tool(),
      get_hubspot_contact_tool(),
      create_hubspot_contact_tool(),
      create_hubspot_note_tool(),
      list_hubspot_deals_tool()
    ]
  end

  @doc """
  Execute a tool call with the given name and arguments.

  Returns {:ok, result} or {:error, reason}.
  """
  def execute_tool(tool_name, arguments, user) do
    case tool_name do
      "search_emails" -> execute_search_emails(arguments, user)
      "search_contacts" -> execute_search_contacts(arguments, user)
      "send_email" -> execute_send_email(arguments, user)
      "create_calendar_event" -> execute_create_calendar_event(arguments, user)
      "list_calendar_events" -> execute_list_calendar_events(arguments, user)
      "search_calendar_events" -> execute_search_calendar_events(arguments, user)
      "get_hubspot_contact" -> execute_get_hubspot_contact(arguments, user)
      "create_hubspot_contact" -> execute_create_hubspot_contact(arguments, user)
      "create_hubspot_note" -> execute_create_hubspot_note(arguments, user)
      "list_hubspot_deals" -> execute_list_hubspot_deals(arguments, user)
      _ -> {:error, "Unknown tool: #{tool_name}"}
    end
  end

  # ============================================================================
  # TOOL DEFINITIONS (LLM Schemas)
  # ============================================================================

  defp search_emails_tool do
    %{
      name: "search_emails",
      description: "Search the user's emails using semantic search (RAG). Use this to find emails about specific topics, people, or keywords.",
      parameters: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description: "The search query (e.g., 'emails from Bill about baseball')"
          },
          limit: %{
            type: "integer",
            description: "Maximum number of results to return (default: 5)"
          }
        },
        required: ["query"]
      }
    }
  end

  defp search_contacts_tool do
    %{
      name: "search_contacts",
      description: "Search HubSpot contacts using semantic search (RAG). Use this to find contacts by description, industry, notes, etc.",
      parameters: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description: "The search query (e.g., 'real estate investors in Boston')"
          },
          limit: %{
            type: "integer",
            description: "Maximum number of results to return (default: 5)"
          }
        },
        required: ["query"]
      }
    }
  end

  defp send_email_tool do
    %{
      name: "send_email",
      description: "Send an email via Gmail. Use this when the user asks to send an email or reply to someone.",
      parameters: %{
        type: "object",
        properties: %{
          to: %{
            type: "string",
            description: "Recipient email address"
          },
          subject: %{
            type: "string",
            description: "Email subject line"
          },
          body: %{
            type: "string",
            description: "Email body content"
          }
        },
        required: ["to", "subject", "body"]
      }
    }
  end

  defp create_calendar_event_tool do
    %{
      name: "create_calendar_event",
      description: "Create a new Google Calendar event. Use this to schedule meetings or appointments.",
      parameters: %{
        type: "object",
        properties: %{
          summary: %{
            type: "string",
            description: "Event title/summary"
          },
          start_time: %{
            type: "string",
            description: "Start time in ISO 8601 format (e.g., '2024-01-15T14:00:00Z')"
          },
          end_time: %{
            type: "string",
            description: "End time in ISO 8601 format"
          },
          description: %{
            type: "string",
            description: "Event description (optional)"
          },
          attendees: %{
            type: "array",
            items: %{type: "string"},
            description: "List of attendee email addresses (optional)"
          }
        },
        required: ["summary", "start_time", "end_time"]
      }
    }
  end

  defp list_calendar_events_tool do
    %{
      name: "list_calendar_events",
      description: "List upcoming calendar events. Use this to see what meetings are scheduled.",
      parameters: %{
        type: "object",
        properties: %{
          days: %{
            type: "integer",
            description: "Number of days to look ahead (default: 7)"
          }
        },
        required: []
      }
    }
  end

  defp search_calendar_events_tool do
    %{
      name: "search_calendar_events",
      description: "Search calendar events by keyword. Use this to find specific meetings or events.",
      parameters: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description: "Search query (e.g., 'baseball', 'Bill', 'quarterly meeting')"
          },
          days: %{
            type: "integer",
            description: "Number of days to search (default: 30)"
          }
        },
        required: ["query"]
      }
    }
  end

  defp get_hubspot_contact_tool do
    %{
      name: "get_hubspot_contact",
      description: "Get a HubSpot contact by email address. Use this to look up contact details.",
      parameters: %{
        type: "object",
        properties: %{
          email: %{
            type: "string",
            description: "Email address of the contact to look up"
          }
        },
        required: ["email"]
      }
    }
  end

  defp create_hubspot_contact_tool do
    %{
      name: "create_hubspot_contact",
      description: "Create a new contact in HubSpot CRM. Use this when the user wants to add a new contact.",
      parameters: %{
        type: "object",
        properties: %{
          email: %{
            type: "string",
            description: "Contact's email address"
          },
          firstname: %{
            type: "string",
            description: "Contact's first name"
          },
          lastname: %{
            type: "string",
            description: "Contact's last name"
          },
          phone: %{
            type: "string",
            description: "Contact's phone number (optional)"
          },
          company: %{
            type: "string",
            description: "Contact's company name (optional)"
          }
        },
        required: ["email"]
      }
    }
  end

  defp create_hubspot_note_tool do
    %{
      name: "create_hubspot_note",
      description: "Create a note in HubSpot associated with a contact. Use this to log interactions.",
      parameters: %{
        type: "object",
        properties: %{
          contact_id: %{
            type: "string",
            description: "HubSpot contact ID to associate the note with"
          },
          body: %{
            type: "string",
            description: "Note content"
          }
        },
        required: ["contact_id", "body"]
      }
    }
  end

  defp list_hubspot_deals_tool do
    %{
      name: "list_hubspot_deals",
      description: "List recent deals from HubSpot CRM. Use this to see current opportunities.",
      parameters: %{
        type: "object",
        properties: %{
          limit: %{
            type: "integer",
            description: "Maximum number of deals to return (default: 20)"
          }
        },
        required: []
      }
    }
  end

  # ============================================================================
  # TOOL EXECUTORS
  # ============================================================================

  defp execute_search_emails(args, user) when is_map(args) do
    # Handle both atom and string keys
    query = args[:query] || args["query"]
    limit = args[:limit] || args["limit"] || 5

    if query do
      case Search.search_emails(user.id, query, limit: limit) do
        {:ok, results} ->
          formatted = Enum.map(results, fn %{email: email, similarity: sim} ->
            %{
              subject: email.subject,
              from: email.from_email,
              date: email.date,
              snippet: String.slice(email.body, 0..200),
              similarity: Float.round(sim, 2)
            }
          end)

          {:ok, %{results: formatted, count: length(formatted)}}

        error ->
          error
      end
    else
      {:error, "Missing required argument: query"}
    end
  end
  defp execute_search_emails(_, _user), do: {:error, "Invalid arguments"}

  defp execute_search_contacts(args, user) when is_map(args) do
    # Handle both atom and string keys
    query = args[:query] || args["query"]
    limit = args[:limit] || args["limit"] || 5

    if query do
      case Search.search_contacts(user.id, query, limit: limit) do
        {:ok, results} ->
          formatted = Enum.map(results, fn %{contact: contact, similarity: sim} ->
            %{
              name: contact.name,
              email: contact.email,
              notes: contact.notes,
              similarity: Float.round(sim, 2)
            }
          end)

          {:ok, %{results: formatted, count: length(formatted)}}

        error ->
          error
      end
    else
      {:error, "Missing required argument: query"}
    end
  end
  defp execute_search_contacts(_, _user), do: {:error, "Invalid arguments"}

  defp execute_send_email(args, user) when is_map(args) do
    # Handle both atom and string keys
    to = args[:to] || args["to"]
    subject = args[:subject] || args["subject"]
    body = args[:body] || args["body"]

    if to && subject && body do
      GmailClient.send_email(user, to: to, subject: subject, body: body)
    else
      {:error, "Missing required arguments: to, subject, body"}
    end
  end
  defp execute_send_email(_, _user), do: {:error, "Invalid arguments"}

  defp execute_create_calendar_event(args, user) when is_map(args) do
    # Handle both atom and string keys
    summary = args[:summary] || args["summary"]
    start_str = args[:start_time] || args["start_time"]
    end_str = args[:end_time] || args["end_time"]

    if summary && start_str && end_str do
      with {:ok, start_dt} <- parse_datetime(start_str),
           {:ok, end_dt} <- parse_datetime(end_str) do

        opts = [
          summary: summary,
          start: start_dt,
          end: end_dt
        ]

        description = args[:description] || args["description"]
        attendees = args[:attendees] || args["attendees"]

        opts = if description, do: Keyword.put(opts, :description, description), else: opts
        opts = if attendees, do: Keyword.put(opts, :attendees, attendees), else: opts

        CalendarClient.create_event(user, opts)
      end
    else
      {:error, "Missing required arguments: summary, start_time, end_time"}
    end
  end
  defp execute_create_calendar_event(_, _user), do: {:error, "Invalid arguments"}

  defp execute_list_calendar_events(args, user) when is_map(args) do
    days = args[:days] || args["days"] || 7
    CalendarClient.get_upcoming_events(user, days: days)
  end
  defp execute_list_calendar_events(_, user) do
    CalendarClient.get_upcoming_events(user, days: 7)
  end

  defp execute_search_calendar_events(%{query: query} = args, user) do
    days = Map.get(args, :days, 30)
    CalendarClient.search_events(user, query, days: days)
  end
  defp execute_search_calendar_events(_, _user), do: {:error, "Missing required argument: query"}

  defp execute_get_hubspot_contact(%{email: email}, user) do
    HubspotClient.search_contact_by_email(user, email)
  end
  defp execute_get_hubspot_contact(_, _user), do: {:error, "Missing required argument: email"}

  defp execute_create_hubspot_contact(%{email: email} = args, user) do
    properties = %{
      email: email,
      firstname: args[:firstname],
      lastname: args[:lastname],
      phone: args[:phone],
      company: args[:company]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()

    HubspotClient.create_contact(user, properties)
  end
  defp execute_create_hubspot_contact(_, _user), do: {:error, "Missing required argument: email"}

  defp execute_create_hubspot_note(%{contact_id: contact_id, body: body}, user) do
    HubspotClient.create_note(user, %{
      body: body,
      associations: [
        %{
          to: %{id: contact_id},
          types: [%{associationCategory: "HUBSPOT_DEFINED", associationTypeId: 202}]
        }
      ]
    })
  end
  defp execute_create_hubspot_note(_, _user), do: {:error, "Missing required arguments: contact_id, body"}

  defp execute_list_hubspot_deals(args, user) do
    limit = Map.get(args, :limit, 20)
    HubspotClient.list_deals(user, limit: limit)
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:error, "Invalid datetime format: #{iso_string}"}
    end
  end
  defp parse_datetime(_), do: {:error, "Datetime must be a string"}
end
