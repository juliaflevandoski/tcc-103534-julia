require "json"
require "net/http"
require "openssl"
require "timeout"
require "uri"

class OpenaiResponsesClient
  ENDPOINT = URI("https://api.openai.com/v1/responses")
  MODEL = "gpt-4o-mini"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 30
  WRITE_TIMEOUT = 10
  MAX_OUTPUT_TOKENS = 3_000

  Result = Struct.new(:data, :error_code, :message, :http_status, keyword_init: true) do
    def success?
      error_code.nil?
    end

    def failure?
      !success?
    end
  end

  def self.call(**arguments)
    new.call(**arguments)
  end

  def initialize(http_factory: nil, api_key_provider: nil)
    @http_factory = http_factory || ->(host, port) { Net::HTTP.new(host, port) }
    @api_key_provider = api_key_provider || -> { ENV["OPENAI_API_KEY"] }
  end

  def call(instructions:, input:, schema_name:, schema:)
    api_key = @api_key_provider.call.to_s.strip
    return failure(:missing_api_key, "A chave da API OpenAI não está configurada.") if api_key.empty?
    return failure(:invalid_request, "Informe instruções, entrada e um schema JSON válido.") unless valid_request?(instructions:, input:, schema_name:, schema:)

    http = @http_factory.call(ENDPOINT.host, ENDPOINT.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.write_timeout = WRITE_TIMEOUT

    request = Net::HTTP::Post.new(ENDPOINT.request_uri)
    request["Authorization"] = "Bearer #{api_key}"
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = JSON.generate(
      model: MODEL,
      instructions:,
      input:,
      max_output_tokens: MAX_OUTPUT_TOKENS,
      text: {
        format: {
          type: "json_schema",
          name: schema_name,
          strict: true,
          schema:
        }
      }
    )

    response = http.request(request)
    response_to_result(response, schema)
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    failure(:timeout, "A comunicação com a API OpenAI excedeu o tempo limite.")
  rescue SocketError, SystemCallError, IOError, EOFError, Net::ProtocolError, OpenSSL::SSL::SSLError
    failure(:connection_error, "Não foi possível conectar à API OpenAI.")
  rescue JSON::GeneratorError
    failure(:invalid_request, "Não foi possível montar a solicitação JSON para a API OpenAI.")
  rescue JSON::ParserError
    failure(:invalid_response, "A API OpenAI retornou uma resposta JSON inválida.")
  end

  private

  def valid_request?(instructions:, input:, schema_name:, schema:)
    instructions.is_a?(String) && instructions.present? &&
      input.is_a?(String) && input.present? &&
      schema_name.is_a?(String) && schema_name.match?(/\A[a-zA-Z0-9_-]{1,64}\z/) &&
      schema.is_a?(Hash) && schema["type"] == "object"
  end

  def response_to_result(response, schema)
    status = response.code.to_i
    return http_failure(status) unless status.between?(200, 299)

    payload = JSON.parse(response.body.to_s)
    return failure(:invalid_response, "A API OpenAI retornou uma resposta incompatível.", status) unless payload.is_a?(Hash)
    return failure(:incomplete_response, "A resposta estruturada da API OpenAI ficou incompleta.", status) if payload["status"] == "incomplete"
    return failure(:invalid_response, "A API OpenAI não concluiu a resposta estruturada.", status) unless payload["status"] == "completed"

    content = Array(payload["output"]).flat_map do |item|
      item.is_a?(Hash) ? Array(item["content"]) : []
    end
    return failure(:refusal, "A solicitação não pôde ser atendida pela API OpenAI.", status) if content.any? { |item| item.is_a?(Hash) && item["type"] == "refusal" }

    output_text = content.filter_map do |item|
      item["text"] if item.is_a?(Hash) && item["type"] == "output_text" && item["text"].is_a?(String)
    end.join
    return failure(:invalid_response, "A API OpenAI não retornou conteúdo JSON estruturado.", status) if output_text.blank?

    data = JSON.parse(output_text)
    unless data.is_a?(Hash) && matches_schema?(data, schema)
      return failure(:invalid_response, "A resposta estruturada da API OpenAI não corresponde ao schema solicitado.", status)
    end

    Result.new(data:, http_status: status)
  end

  def matches_schema?(value, schema)
    return false unless schema.is_a?(Hash)
    if schema.key?("anyOf")
      alternatives = schema["anyOf"]
      return alternatives.is_a?(Array) && alternatives.any? { |alternative| matches_schema?(value, alternative) }
    end

    return false unless schema_type_matches?(value, schema["type"])
    return false if schema.key?("enum") && !schema["enum"].include?(value)

    case schema["type"]
    when "object"
      properties = schema.fetch("properties", {})
      required = schema.fetch("required", [])
      return false unless properties.is_a?(Hash) && required.is_a?(Array)
      return false unless (required - value.keys).empty?
      return false if schema["additionalProperties"] == false && (value.keys - properties.keys).any?

      properties.all? do |key, property_schema|
        !value.key?(key) || matches_schema?(value[key], property_schema)
      end
    when "array"
      return false if schema.key?("minItems") && value.length < schema["minItems"]
      return false if schema.key?("maxItems") && value.length > schema["maxItems"]

      !schema.key?("items") || value.all? { |item| matches_schema?(item, schema["items"]) }
    else
      true
    end
  end

  def schema_type_matches?(value, type)
    case type
    when "object" then value.is_a?(Hash)
    when "array" then value.is_a?(Array)
    when "string" then value.is_a?(String)
    when "number" then value.is_a?(Numeric)
    when "integer" then value.is_a?(Integer)
    when "boolean" then value == true || value == false
    when "null" then value.nil?
    else false
    end
  end

  def http_failure(status)
    case status
    when 401, 403
      failure(:invalid_api_key, "A API OpenAI recusou a chave ou as permissões configuradas.", status)
    when 429
      failure(:rate_limited, "O limite de requisições da API OpenAI foi atingido.", status)
    when 500..599
      failure(:service_unavailable, "A API OpenAI está temporariamente indisponível.", status)
    else
      failure(:http_error, "A solicitação à API OpenAI falhou.", status)
    end
  end

  def failure(error_code, message, http_status = nil)
    Result.new(data: nil, error_code:, message:, http_status:)
  end
end
