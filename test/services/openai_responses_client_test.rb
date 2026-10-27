require "test_helper"

class OpenaiResponsesClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  class FakeHttp
    attr_accessor :use_ssl, :open_timeout, :read_timeout, :write_timeout
    attr_reader :requests

    def initialize(response: nil, error: nil)
      @response = response
      @error = error
      @requests = []
    end

    def request(request)
      @requests << request
      raise @error if @error

      @response
    end
  end

  setup do
    @schema = {
      "type" => "object",
      "properties" => { "questions" => { "type" => "array", "items" => { "type" => "object" } } },
      "required" => [ "questions" ],
      "additionalProperties" => false
    }
  end

  test "fails before networking when the API key is absent" do
    result, http = invoke(api_key: nil, response: successful_response)

    assert result.failure?
    assert_equal :missing_api_key, result.error_code
    assert_nil result.data
    assert_empty http.requests
  end

  test "sends a structured output request and parses a successful JSON object" do
    result, http = invoke(response: successful_response)
    request = http.requests.fetch(0)
    body = JSON.parse(request.body)
    format = body.dig("text", "format")

    assert result.success?
    assert_equal({ "questions" => [] }, result.data)
    assert_equal 200, result.http_status
    assert_equal "Bearer test-secret-key", request["Authorization"]
    assert_equal "application/json", request["Content-Type"]
    assert_equal OpenaiResponsesClient::MODEL, body["model"]
    assert_equal "QuizDraft", format["name"]
    assert_equal true, format["strict"]
    assert_equal @schema, format["schema"]
    assert_equal true, http.use_ssl
    assert_equal OpenaiResponsesClient::OPEN_TIMEOUT, http.open_timeout
    assert_equal OpenaiResponsesClient::READ_TIMEOUT, http.read_timeout
    assert_equal OpenaiResponsesClient::WRITE_TIMEOUT, http.write_timeout
  end

  test "validates anyOf branches and array item limits in structured output schemas" do
    schema = {
      "type" => "object",
      "properties" => {
        "items" => {
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 1,
          "items" => {
            "anyOf" => [
              object_schema("multiple_choice", %w[question_type statement options correct_option_ids]),
              object_schema("true_false", %w[question_type statement correct_option_ids])
            ]
          }
        }
      },
      "required" => [ "items" ],
      "additionalProperties" => false
    }
    response = Response.new("200", successful_payload({ "items" => [ { "question_type" => "true_false", "statement" => "Q", "correct_option_ids" => [ "true" ] } ] }.to_json).to_json)
    result, = invoke(response:, schema:)

    assert result.success?
  end

  test "rejects structured output outside anyOf branches or array limits" do
    schema = {
      "type" => "object",
      "properties" => {
        "items" => {
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 1,
          "items" => { "anyOf" => [ object_schema("true_false", %w[question_type statement correct_option_ids]) ] }
        }
      },
      "required" => [ "items" ],
      "additionalProperties" => false
    }
    invalid_outputs = [
      { "items" => [ { "question_type" => "unexpected", "statement" => "Q", "correct_option_ids" => [ "true" ] } ] },
      { "items" => [] },
      { "items" => [ 1, 2 ] }
    ]

    invalid_outputs.each do |output|
      response = Response.new("200", successful_payload(output.to_json).to_json)
      result, = invoke(response:, schema:)

      assert result.failure?
      assert_equal :invalid_response, result.error_code
    end
  end

  test "maps invalid credentials, rate limits, and service outages without exposing response bodies" do
    [
      [ "401", :invalid_api_key ],
      [ "429", :rate_limited ],
      [ "503", :service_unavailable ]
    ].each do |status, error_code|
      result, = invoke(response: Response.new(status, { "error" => "test-secret-key" }.to_json))

      assert result.failure?
      assert_equal error_code, result.error_code
      assert_not_includes result.message, "test-secret-key"
    end
  end

  test "maps other HTTP failures" do
    result, = invoke(response: Response.new("400", { "error" => "bad request" }.to_json))

    assert result.failure?
    assert_equal :http_error, result.error_code
    assert_equal 400, result.http_status
  end

  test "handles timeout and connection errors without retrying" do
    [
      [ Net::ReadTimeout.new("test timeout"), :timeout ],
      [ SocketError.new("test connection error"), :connection_error ]
    ].each do |error, error_code|
      result, http = invoke(error:)

      assert result.failure?
      assert_equal error_code, result.error_code
      assert_equal 1, http.requests.length
    end
  end

  test "rejects malformed, incomplete, refused, and non-object structured responses" do
    responses = [
      [ Response.new("200", "not-json"), :invalid_response ],
      [ Response.new("200", { "status" => "incomplete" }.to_json), :incomplete_response ],
      [ Response.new("200", refusal_response.to_json), :refusal ],
      [ Response.new("200", successful_payload("[]").to_json), :invalid_response ],
      [ Response.new("200", successful_payload({ "other" => true }.to_json).to_json), :invalid_response ]
    ]

    responses.each do |response, error_code|
      result, = invoke(response:)

      assert result.failure?
      assert_equal error_code, result.error_code
      assert_nil result.data
    end
  end

  test "rejects invalid request configuration before networking" do
    http = FakeHttp.new(response: successful_response)
    result = build_client(http, "test-secret-key").call(
      instructions: "",
      input: "quiz",
      schema_name: "QuizDraft",
      schema: @schema
    )

    assert result.failure?
    assert_equal :invalid_request, result.error_code
    assert_empty http.requests
  end

  private

  def invoke(api_key: "test-secret-key", response: nil, error: nil, schema: @schema)
    http = FakeHttp.new(response:, error:)
    client = build_client(http, api_key)
    result = client.call(
      instructions: "Return a quiz JSON object.",
      input: "Create one sample question.",
      schema_name: "QuizDraft",
      schema:
    )
    [ result, http ]
  end

  def build_client(http, api_key)
    OpenaiResponsesClient.new(
      http_factory: ->(_host, _port) { http },
      api_key_provider: -> { api_key }
    )
  end

  def successful_response
    Response.new("200", successful_payload({ "questions" => [] }.to_json).to_json)
  end

  def successful_payload(output_text)
    {
      "status" => "completed",
      "output" => [
        { "type" => "message", "content" => [ { "type" => "output_text", "text" => output_text } ] }
      ]
    }
  end

  def object_schema(question_type, required)
    properties = required.to_h do |name|
      value_schema = name == "question_type" ? { "type" => "string", "enum" => [ question_type ] } : { "type" => "string" }
      [ name, value_schema ]
    end
    properties["options"] = { "type" => "array", "items" => { "type" => "string" } } if required.include?("options")
    properties["correct_option_ids"] = { "type" => "array", "items" => { "type" => "string" } } if required.include?("correct_option_ids")

    {
      "type" => "object",
      "properties" => properties,
      "required" => required,
      "additionalProperties" => false
    }
  end

  def refusal_response
    {
      "status" => "completed",
      "output" => [
        { "type" => "message", "content" => [ { "type" => "refusal", "refusal" => "Request refused" } ] }
      ]
    }
  end
end
