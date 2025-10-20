defmodule FinancialAdvisorAi.Integrations.HubspotClient do
  @moduledoc """
  HubSpot CRM API client for managing contacts, companies, and deals.
  Automatically handles token refresh when needed.
  """

  require Logger
  alias FinancialAdvisorAi.Accounts.User
  alias FinancialAdvisorAiWeb.AuthController

  @hubspot_api_base "https://api.hubapi.com"

  # ============================================================================
  # CONTACTS
  # ============================================================================

  @doc """
  List all contacts.

  ## Options
    * `:limit` - Number of contacts to return (default: 100)
    * `:properties` - List of properties to include
    * `:after` - Pagination cursor

  ## Examples

      iex> HubspotClient.list_contacts(user)
      {:ok, %{results: [...], paging: %{next: %{after: "..."}}}}
  """
  def list_contacts(%User{} = user, opts \\ []) do
    with {:ok, user} <- AuthController.ensure_hubspot_token(user) do
      limit = Keyword.get(opts, :limit, 100)
      properties = Keyword.get(opts, :properties, default_contact_properties())

      params = %{
        limit: limit,
        properties: Enum.join(properties, ",")
      }

      params = if opts[:after], do: Map.put(params, :after, opts[:after]), else: params

      url = "#{@hubspot_api_base}/crm/v3/objects/contacts?#{URI.encode_query(params)}"
      headers = [{"Authorization", "Bearer #{user.hubspot_access_token}"}]

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, parse_contacts_response(response)}

        {:ok, %{status: status, body: body}} ->
          Logger.error("HubSpot list_contacts error: #{status} - #{inspect(body)}")
          {:error, "Failed to list contacts: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Get all contacts (handles pagination automatically).

  ## Examples

      iex> HubspotClient.get_all_contacts(user)
      {:ok, [%{id: "...", email: "...", ...}, ...]}
  """
  def get_all_contacts(%User{} = user, opts \\ []) do
    get_all_contacts_recursive(user, opts, [])
  end

  defp get_all_contacts_recursive(user, opts, accumulated) do
    case list_contacts(user, opts) do
      {:ok, %{results: results, paging: paging}} ->
        all_contacts = accumulated ++ results

        if paging && paging[:next] && paging[:next][:after] do
          # More pages available
          new_opts = Keyword.put(opts, :after, paging[:next][:after])
          get_all_contacts_recursive(user, new_opts, all_contacts)
        else
          # No more pages
          {:ok, all_contacts}
        end

      error ->
        error
    end
  end

  @doc """
  Get a single contact by ID.

  ## Examples

      iex> HubspotClient.get_contact(user, "123456")
      {:ok, %{id: "123456", email: "contact@example.com", ...}}
  """
  def get_contact(%User{} = user, contact_id, opts \\ []) do
    with {:ok, user} <- AuthController.ensure_hubspot_token(user) do
      properties = Keyword.get(opts, :properties, default_contact_properties())

      params = %{properties: Enum.join(properties, ",")}
      url = "#{@hubspot_api_base}/crm/v3/objects/contacts/#{contact_id}?#{URI.encode_query(params)}"
      headers = [{"Authorization", "Bearer #{user.hubspot_access_token}"}]

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, parse_contact(response)}

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to get contact: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Search contacts by email.

  ## Examples

      iex> HubspotClient.search_contact_by_email(user, "bill@example.com")
      {:ok, %{id: "...", email: "bill@example.com", ...}}
  """
  def search_contact_by_email(%User{} = user, email) do
    search_contacts(user, %{
      filterGroups: [
        %{
          filters: [
            %{
              propertyName: "email",
              operator: "EQ",
              value: email
            }
          ]
        }
      ]
    })
  end

  @doc """
  Search contacts with custom filters.

  ## Examples

      iex> HubspotClient.search_contacts(user, %{
        filterGroups: [
          %{filters: [%{propertyName: "city", operator: "EQ", value: "Boston"}]}
        ],
        limit: 50
      })
      {:ok, [%{id: "...", city: "Boston", ...}, ...]}
  """
  def search_contacts(%User{} = user, search_body) do
    with {:ok, user} <- AuthController.ensure_hubspot_token(user) do
      url = "#{@hubspot_api_base}/crm/v3/objects/contacts/search"
      headers = [
        {"Authorization", "Bearer #{user.hubspot_access_token}"},
        {"Content-Type", "application/json"}
      ]

      case Req.post(url, json: search_body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          results = response["results"] || []
          {:ok, Enum.map(results, &parse_contact/1)}

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to search contacts: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Create a new contact.

  ## Examples

      iex> HubspotClient.create_contact(user, %{
        email: "newcontact@example.com",
        firstname: "John",
        lastname: "Doe",
        phone: "555-1234"
      })
      {:ok, %{id: "...", email: "newcontact@example.com", ...}}
  """
  def create_contact(%User{} = user, properties) do
    with {:ok, user} <- AuthController.ensure_hubspot_token(user) do
      url = "#{@hubspot_api_base}/crm/v3/objects/contacts"
      headers = [
        {"Authorization", "Bearer #{user.hubspot_access_token}"},
        {"Content-Type", "application/json"}
      ]

      body = %{properties: properties}

      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 201, body: response}} ->
          {:ok, parse_contact(response)}

        {:ok, %{status: status, body: body}} ->
          Logger.error("HubSpot create_contact error: #{status} - #{inspect(body)}")
          {:error, "Failed to create contact: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Update an existing contact.

  ## Examples

      iex> HubspotClient.update_contact(user, "123456", %{
        phone: "555-9999",
        notes: "Updated notes"
      })
      {:ok, %{id: "123456", phone: "555-9999", ...}}
  """
  def update_contact(%User{} = user, contact_id, properties) do
    with {:ok, user} <- AuthController.ensure_hubspot_token(user) do
      url = "#{@hubspot_api_base}/crm/v3/objects/contacts/#{contact_id}"
      headers = [
        {"Authorization", "Bearer #{user.hubspot_access_token}"},
        {"Content-Type", "application/json"}
      ]

      body = %{properties: properties}

      case Req.patch(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, parse_contact(response)}

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to update contact: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  # ============================================================================
  # COMPANIES
  # ============================================================================

  @doc """
  List companies.

  ## Examples

      iex> HubspotClient.list_companies(user, limit: 50)
      {:ok, %{results: [...], paging: ...}}
  """
  def list_companies(%User{} = user, opts \\ []) do
    with {:ok, user} <- AuthController.ensure_hubspot_token(user) do
      limit = Keyword.get(opts, :limit, 100)
      properties = Keyword.get(opts, :properties, default_company_properties())

      params = %{
        limit: limit,
        properties: Enum.join(properties, ",")
      }

      params = if opts[:after], do: Map.put(params, :after, opts[:after]), else: params

      url = "#{@hubspot_api_base}/crm/v3/objects/companies?#{URI.encode_query(params)}"
      headers = [{"Authorization", "Bearer #{user.hubspot_access_token}"}]

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, parse_companies_response(response)}

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to list companies: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Create a new company.

  ## Examples

      iex> HubspotClient.create_company(user, %{
        name: "Acme Corp",
        domain: "acme.com",
        industry: "Technology"
      })
      {:ok, %{id: "...", name: "Acme Corp", ...}}
  """
  def create_company(%User{} = user, properties) do
    with {:ok, user} <- AuthController.ensure_hubspot_token(user) do
      url = "#{@hubspot_api_base}/crm/v3/objects/companies"
      headers = [
        {"Authorization", "Bearer #{user.hubspot_access_token}"},
        {"Content-Type", "application/json"}
      ]

      body = %{properties: properties}

      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 201, body: response}} ->
          {:ok, parse_company(response)}

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to create company: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  # ============================================================================
  # DEALS
  # ============================================================================

  @doc """
  List deals.

  ## Examples

      iex> HubspotClient.list_deals(user, limit: 50)
      {:ok, %{results: [...], paging: ...}}
  """
  def list_deals(%User{} = user, opts \\ []) do
    with {:ok, user} <- AuthController.ensure_hubspot_token(user) do
      limit = Keyword.get(opts, :limit, 100)
      properties = Keyword.get(opts, :properties, default_deal_properties())

      params = %{
        limit: limit,
        properties: Enum.join(properties, ",")
      }

      params = if opts[:after], do: Map.put(params, :after, opts[:after]), else: params

      url = "#{@hubspot_api_base}/crm/v3/objects/deals?#{URI.encode_query(params)}"
      headers = [{"Authorization", "Bearer #{user.hubspot_access_token}"}]

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, parse_deals_response(response)}

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to list deals: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Create a new deal.

  ## Examples

      iex> HubspotClient.create_deal(user, %{
        dealname: "New Opportunity",
        amount: "50000",
        dealstage: "appointmentscheduled"
      })
      {:ok, %{id: "...", dealname: "New Opportunity", ...}}
  """
  def create_deal(%User{} = user, properties) do
    with {:ok, user} <- AuthController.ensure_hubspot_token(user) do
      url = "#{@hubspot_api_base}/crm/v3/objects/deals"
      headers = [
        {"Authorization", "Bearer #{user.hubspot_access_token}"},
        {"Content-Type", "application/json"}
      ]

      body = %{properties: properties}

      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 201, body: response}} ->
          {:ok, parse_deal(response)}

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to create deal: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  # ============================================================================
  # NOTES
  # ============================================================================

  @doc """
  Create a note associated with a contact, company, or deal.

  ## Examples

      iex> HubspotClient.create_note(user, %{
        body: "Had a great call with the client",
        associations: [%{to: %{id: "123456"}, type: "note_to_contact"}]
      })
      {:ok, %{id: "...", body: "Had a great call...", ...}}
  """
  def create_note(%User{} = user, note_data) do
    with {:ok, user} <- AuthController.ensure_hubspot_token(user) do
      url = "#{@hubspot_api_base}/crm/v3/objects/notes"
      headers = [
        {"Authorization", "Bearer #{user.hubspot_access_token}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        properties: %{
          hs_note_body: note_data[:body] || note_data["body"]
        },
        associations: note_data[:associations] || note_data["associations"] || []
      }

      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 201, body: response}} ->
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          {:error, "Failed to create note: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp default_contact_properties do
    ["email", "firstname", "lastname", "phone", "company", "jobtitle", "city", "state", "country", "notes"]
  end

  defp default_company_properties do
    ["name", "domain", "industry", "city", "state", "country", "phone", "numberofemployees"]
  end

  defp default_deal_properties do
    ["dealname", "amount", "dealstage", "closedate", "pipeline", "dealtype"]
  end

  defp parse_contacts_response(response) do
    %{
      results: Enum.map(response["results"] || [], &parse_contact/1),
      paging: parse_paging(response["paging"])
    }
  end

  defp parse_companies_response(response) do
    %{
      results: Enum.map(response["results"] || [], &parse_company/1),
      paging: parse_paging(response["paging"])
    }
  end

  defp parse_deals_response(response) do
    %{
      results: Enum.map(response["results"] || [], &parse_deal/1),
      paging: parse_paging(response["paging"])
    }
  end

  defp parse_contact(contact) do
    props = contact["properties"] || %{}

    %{
      id: contact["id"],
      email: props["email"],
      name: build_full_name(props["firstname"], props["lastname"]),
      firstname: props["firstname"],
      lastname: props["lastname"],
      phone: props["phone"],
      company: props["company"],
      jobtitle: props["jobtitle"],
      city: props["city"],
      state: props["state"],
      country: props["country"],
      notes: props["notes"],
      properties: props,
      created_at: contact["createdAt"],
      updated_at: contact["updatedAt"]
    }
  end

  defp parse_company(company) do
    props = company["properties"] || %{}

    %{
      id: company["id"],
      name: props["name"],
      domain: props["domain"],
      industry: props["industry"],
      city: props["city"],
      state: props["state"],
      country: props["country"],
      phone: props["phone"],
      number_of_employees: props["numberofemployees"],
      properties: props,
      created_at: company["createdAt"],
      updated_at: company["updatedAt"]
    }
  end

  defp parse_deal(deal) do
    props = deal["properties"] || %{}

    %{
      id: deal["id"],
      name: props["dealname"],
      amount: props["amount"],
      stage: props["dealstage"],
      close_date: props["closedate"],
      pipeline: props["pipeline"],
      deal_type: props["dealtype"],
      properties: props,
      created_at: deal["createdAt"],
      updated_at: deal["updatedAt"]
    }
  end

  defp parse_paging(nil), do: nil
  defp parse_paging(paging) do
    %{
      next: paging["next"]
    }
  end

  defp build_full_name(nil, nil), do: nil
  defp build_full_name(first, nil), do: first
  defp build_full_name(nil, last), do: last
  defp build_full_name(first, last), do: "#{first} #{last}"
end
