require "http/client"
require "http"
require "uri"
require "json"

module Spu
  VERSION     = "0.1.0"
  TIMEZONE    = "America/Los_Angeles"
  SERVICE_MAP = Hash(String, Service){
    "Garbage"         => Service::Garbage,
    "Recycle"         => Service::Recycle,
    "Food/Yard Waste" => Service::YardWaste,
  }

  enum Service
    Garbage
    Recycle
    YardWaste
  end

  class Account
    PREM_CODE_URL    = "https://myutilities.seattle.gov/rest/serviceorder/findaddress"
    ACCOUNT_CODE_URL = "https://myutilities.seattle.gov/rest/serviceorder/findAccount"
    SERVICES_URL     = "https://myutilities.seattle.gov/rest/guest/swsummary"
    CALENDAR_URL     = "https://myutilities.seattle.gov/rest/solidwastecalendar"

    @service_points : Hash(String, String)
    @calendar : CollectionCalendar

    getter address : String
    getter account_number : String
    getter premise_code : String?
    getter person_id : String?
    getter company_code : String?

    def initialize(@address)
      @account_number = request_account_number
      @service_points = request_service_points
      @calendar = request_collection_calendar
    end

    # Return Hash(Date => CollectionDay)
    # Contains a single date
    def next_collection_day : CollectionDay?
      @calendar.next_day
    end

    # Return Hash(Date => CollectionDay)
    # Contains all dates
    def collection_schedule : Hash(String, CollectionDay)?
      @calendar.schedule
    end

    private def request_service_points
      headers = Authorization.header
      payload = {
        "customerId":     "guest",
        "accountContext": {
          "accountNumber":  @account_number,
          "personId":       nil,
          "companyCd":      nil,
          "serviceAddress": nil,
        },
      }
      response = request(SERVICES_URL, payload, headers)
      @person_id = response["accountContext"]["personId"].to_s
      @company_code = response["accountContext"]["companyCd"].to_s

      services = response["accountSummaryType"]["swServices"][0]["services"].as_a
      @service_points = services.map { |s| {s["description"].to_s, s["servicePointId"].to_s} }.to_h
    end

    private def request_prem_code
      response = request(PREM_CODE_URL, {
        "address" => {
          "addressLine1" => @address,
          "city"         => "",
          "zip"          => "",
        },
      })
      raise RequestError.new("Unable to recognize address: #{@address}") if response["address"].size == 0
      @premise_code = response["address"][0]["premCode"].to_s
    end

    private def request_account_number
      prem_code = request_prem_code
      response = request(ACCOUNT_CODE_URL, {
        "address" => {
          "premCode" => prem_code,
        },
      })
      # raise RequestError.new("Unable to locate an account at #{@address}") if response["account"]["accountNumber"].as_s?.nil?
      @account_number = response["account"]["accountNumber"].to_s
    end

    private def request_collection_calendar
      headers = Authorization.header
      payload = {
        "customerId":     "guest",
        "accountContext": {
          "accountNumber": @account_number,
          "personId":      @person_id,
          "companyCd":     @company_code,
        },
        "servicePoints": @service_points.values,
      }
      response = request(CALENDAR_URL, payload, headers)
      calendar_response = response["calendar"].as_h # service point => [dates]
      calendar = CollectionCalendar.new
      @service_points.each do |k, v|
        dates = Array(String).from_json(calendar_response[v].to_s).map { |d| format_date(d) }
        calendar.add_days(k, dates)
      end
      calendar
    end

    private def format_date(date_string : String) : String
      date_parts = date_string.split('/')
      date = Time.local(
        date_parts[2].to_i,
        date_parts[0].to_i,
        date_parts[1].to_i,
        0, 0, 0,
        location: Time::Location.load(Spu::TIMEZONE))
        .to_s("%F")
    end

    private def request(url, payload, headers = nil)
      JSON::Any.from_json(Spu::Request.send(url, payload, headers))
    end
  end

  struct CollectionDay
    getter date : Time
    getter services : Set(Service) = Set(Service).new

    def initialize(date : String)
      @date = Time.parse(date, "%F", Time::Location.load(Spu::TIMEZONE))
    end

    def add(service : String)
      if service = Spu::SERVICE_MAP[service]
        services.add(service)
      end
    end

    def <=>(other : CollectionDay) : Int32
      self.date <=> other.date
    end
  end

  struct CollectionCalendar
    getter schedule : Hash(String, CollectionDay)

    def initialize
      @schedule = Hash(String, CollectionDay).new
    end

    # throw if no entries in schedule
    def next_day
      today = Time.local(Time::Location.load(Spu::TIMEZONE)).to_s("%F")
      next_day = @schedule.keys.sort.find { |d| d >= today }
      @schedule[next_day]
    end

    def add_days(service : String, dates : Array(String))
      dates.each do |date|
        collection_day = @schedule[date]? || CollectionDay.new(date)
        collection_day.add(service)
        @schedule[date] = collection_day
      end
    end
  end

  class Authorization
    URL = "https://myutilities.seattle.gov/rest/auth/guest"
    getter auth_header : HTTP::Headers

    private def initialize
      auth_response = JSON::Any.from_json(request_token("guest", "guest"))
      token = auth_response["access_token"]
      @auth_header = HTTP::Headers{"Authorization" => "Bearer #{token}"}
    end

    def self.header
      self.instance.auth_header
    end

    def self.instance
      @@instance ||= new
    end

    private def request_token(username : String, password : String)
      payload = {
        "grant_type" => "password",
        "username"   => "guest",
        "password"   => "guest",
      }
      Spu::Request.send(URL, payload)
    end
  end

  class Request
    def self.send(url, payload, headers = nil)
      uri = URI.parse(url)
      request("POST", uri, payload.to_json, headers)
    end

    private def self.request(method : String, uri : URI, payload, headers : HTTP::Headers? = nil)
      final_headers = HTTP::Headers{"Content-Type" => "application/json", "Accept" => "application/json"}
      final_headers.merge!(headers) if headers
      response = HTTP::Client.post uri, headers: final_headers, body: payload
      process_response(response)
    end

    private def self.process_response(response : HTTP::Client::Response)
      response.body if is_valid(response)
    end

    private def self.is_valid(response : HTTP::Client::Response)
      case response.status_code
      when 200..299
        return true
      else
        raise Spu::RequestError.new("#{response.status_code}: #{response.status_message}")
      end
    end
  end

  class Spu::RequestError < Exception
  end
end
