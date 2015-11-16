module Wpclient
  class Connection
    attr_reader :url, :username

    def initialize(url:, username:, password:)
      @url = url
      @username = username
      @password = password
    end

    def get(model, path, params = {})
      model.parse(get_json(path, params))
    end

    def get_multiple(model, path, params = {})
      get_json(path, params).map { |data| model.parse(data) }
    end

    def create(model, path, attributes, redirect_params: {})
      response = send_json(path, attributes)

      if response.status == 201 # Created
        model.parse(get_json(response.headers.fetch("location"), redirect_params))
      else
        handle_status_code(response)
        model.parse(parse_json_response(response))
      end
    end

    def create_without_response(path, attributes)
      response = send_json(path, attributes)

      if response.status == 201 # Created
        true
      else
        handle_status_code(response)
        true
      end
    end

    def delete(path, attributes = {})
      response = send_json(path, attributes, method: :delete)
      handle_status_code(response)
      true
    end

    def patch(model, path, attributes)
      model.parse(
        parse_json_response(send_json(path, attributes, method: :patch))
      )
    end

    def patch_without_response(path, attributes)
      handle_status_code(send_json(path, attributes, method: :patch))
      true
    end

    def inspect
      "#<#{self.class.name} #@username @ #@url>"
    end

    private
    def net
      @net ||= setup_network_connection
    end

    def setup_network_connection
      Faraday.new(url: "#{url}/wp/v2") do |conn|
        conn.request :basic_auth, username, @password
        conn.adapter :net_http
      end
    end

    def get_json(path, params = {})
      parse_json_response(net.get(path, params))
    rescue Faraday::TimeoutError
      raise TimeoutError
    end

    def send_json(path, data, method: :post)
      unless %i[get post put patch delete].include? method
        raise ArgumentError, "Invalid method: #{method.inspect}"
      end

      net.public_send(method) do |request|
        json = data.to_json
        request.url path
        request.headers["Content-Type"] = "application/json; charset=#{json.encoding}"
        request.body = json
      end
    rescue Faraday::TimeoutError
      raise TimeoutError
    end

    def parse_json_response(response)
      handle_status_code(response)

      content_type = response.headers["content-type"].split(";").first
      unless content_type == "application/json"
        raise ServerError, "Got content type #{content_type}"
      end

      JSON.parse(response.body)

    rescue JSON::ParserError => error
      raise ServerError, "Could not parse JSON response: #{error}"
    end

    def handle_status_code(response)
      case response.status
      when 200
        return
      when 404
        raise NotFoundError, "Could not find resource"
      when 400
        handle_bad_request(response)
      else
        raise ServerError, "Server returned status code #{response.status}: #{response.body}"
      end
    end

    def handle_bad_request(response)
      code, message = bad_request_details(response)
      if code == "rest_post_invalid_id"
        raise NotFoundError, "Post ID is not found"
      else
        raise ValidationError, message
      end
    end

    def bad_request_details(response)
      details = JSON.parse(response.body).first
      [details["code"], details["message"]]
    rescue
      [nil, "Bad Request"]
    end
  end
end
