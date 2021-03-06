# encoding: UTF-8

require 'spec_helper'

include Grape::ClientGenerator::Ruby

describe RubyGenerator do
  describe "#generate_each" do
    it "generates the right files" do
      generator = RubyGenerator.new([DummyEndpoints], {
        :response_types => [:xml, :json]
      })

      file_names = []
      generator.generate_each { |file_name, contents| file_names << file_name }
      file_names.should == [
        "api.rb",
        "xml_response_parser.rb",
        "json_response_parser.rb"
      ]
    end
  end

  describe "generated classes" do
    before(:all) do
      generator = RubyGenerator.new([DummyEndpoints], {
        :response_types => [:xml, :json],
        :namespace => "MyClient",
        :default_format => "xml",
        :default_version => "v1"
      })

      @api_module = Module.new do
        generator.generate_each do |file_name, contents|
          class_eval(contents)
        end
      end
    end

    it "defines the correct classes" do
      @api_module.constants.should include(:MyClient)

      [:Api, :XmlResponseParser, :JsonResponseParser].each do |const_sym|
        @api_module::MyClient.constants.should include(const_sym)
      end
    end

    describe "generated api class" do
      let(:generic_xml_http_response) do
        Class.new do
          def body
            "<some-xml-response></some-xml-response>"
          end
        end.new
      end

      before(:each) do
        @api = @api_module::MyClient::Api.new("http://twitter.com")
      end

      it "properly fires off a get request" do
        expected_uri = URI.parse("http://twitter.com/v1/kirk.xml/?foo=bar&juicy=kale")
        mock(Net::HTTP).get_response(expected_uri) { generic_xml_http_response }

        @api.kirk(
          :foo => "bar",
          :juicy => "kale"
        )
      end

      it "properly fires off a post request" do
        expected_uri = URI.parse("http://twitter.com/v1/shaggy.xml")

        any_instance_of(Net::HTTP) do |http|
          mock(http).request(anything) do |req|
            # we have to assume the host is correct since net/http won't give it to us in this context
            req.path.should == "/v1/shaggy.xml"
            req.body.should == "foo=bar&juicy=kale"

            generic_xml_http_response
          end
        end

        @api.shaggy(
          :foo => "bar",
          :juicy => "kale"
        )
      end
    end

    describe "generated json response parser class" do
      let(:parser) { @api_module::MyClient::JsonResponseParser }

      describe("#parse") do
        it "parses a json response successfully" do
          parser.parse('{"hello": "world"}').should == { "hello" => "world" }
        end
      end
    end

    describe "generated xml response parser class" do
      let(:parser) { @api_module::MyClient::XmlResponseParser }

      describe("#parse") do
        it "uses 'error' as the root if given an error-ish response" do
          response = %q(<error><message>jelly beans</message></error>)
          parser.parse(response).should == {
            "error" => {
              "message" => {
                "value" => "jelly beans"
              }
            }
          }
        end

        it "handles a single-element hash response" do
          response = %q(<hash><dumbledore>wizard</dumbledore></hash>)
          parser.parse(response).should == {
            "response" => {
              "dumbledore" => {
                "value" => "wizard"
              }
            }
          }
        end

        it "handles an array response" do
          response = %q(<strings type="array">)
            response += %q(<string>gryffindor</string><string>hufflepuff</string>)
            response += %q(<string>ravenclaw</string><string>slytherin</string>)
          response += %q(</strings>)

          parser.parse(response).should == {
            "response" => ["gryffindor", "hufflepuff", "ravenclaw", "slytherin"]
          }
        end

        it "handles a nested hash and array combination" do
          response = %q(<hash>) +
            %q(<houses type="array">) +
              %q(<house>gryffindor</house>) +
              %q(<house>hufflepuff</house>) +
              %q(<house>ravenclaw</house>) +
              %q(<house>slytherin</house>) +
            %q(</houses>) +
            %q(<friends type="array">) +
              %q(<friend>moony</friend>) +
              %q(<friend>wormtail</friend>) +
              %q(<friend>padfoot</friend>) +
              %q(<friend>prongs</friend>) +
            %q(</friends>) +
          %q(</hash>)

          parser.parse(response).should == {
            "response" => {
              "houses" => {
                "type" => "array",
                "value" => ["gryffindor", "hufflepuff", "ravenclaw", "slytherin"]
              },
              "friends" => {
                "type" => "array",
                "value" => ["moony", "wormtail", "padfoot", "prongs"]
              }
            }
          }
        end
      end
    end
  end
end