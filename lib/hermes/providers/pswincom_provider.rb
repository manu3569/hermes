#encoding: utf-8
require "httpclient"

module Hermes
  module Providers

    class PSWinComProvider

      attr_reader :user
      attr_reader :password

      URL = "https://sms.pswin.com/http4sms/sendRef.asp".freeze
      DEFAULT_SENDER_COUNTRY = 'NO'.freeze
      DEFAULT_PREFIX = '47'.freeze
      CONVERSION_OPTIONS = {
        :undef => :replace,
        :replace => ''
      }

      class PSWinComError < ProviderError; end
      class APIFailureError < PSWinComError; end

      def initialize(options = {})
        options.assert_valid_keys(:user, :password, :default_sender_number, :default_prefix, :default_sender_country)
        @user = options[:user]
        raise ConfigurationError, "User must be specified" unless @user
        @password = options[:password]
        raise ConfigurationError, "Password must be specified" unless @password
        @default_prefix = options[:default_prefix] || DEFAULT_PREFIX
        @default_sender_country = options[:default_sender_country] || DEFAULT_SENDER_COUNTRY
        @default_sender_number = options[:default_sender_number]
      end

      def send_message!(options)
        options.assert_valid_keys(:receipt_url, :rate, :sender_number, :recipient_number, :text, :bill)
        raise Hermes::OptionMissingError.new("recipient_number is missing") unless options[:recipient_number]
        raise Hermes::OptionMissingError.new("text is missing") unless options[:text]
        response = HTTPClient.new.post(
          URL,
          post_data(
            options[:text],
            options[:recipient_number],
            options[:sender_number]
          )
        )
        raise APIFailureError.new(response.body) if [310, 312, 500].include?(response.status)
        raise InvalidResponseError.new(response.body) if [302, 202, 404].include?(response.status)
        data = response.body.split("\n")
        raise InvalidResponseError.new(response.body) if data[2].blank?
        return data[2].strip if data[0].strip == "0" # Return reference ID if status is 0 (valid)
        raise MessageRejectedError.new(response.body)
      end

      # Test whether provider is functional. Returns true or false.
      def test!
        begin
          send_message!(:recipient_number => '_', :body => '')
        rescue Excon::Errors::Error
          false
        rescue MessageRejectedError
          true
        else
          false  # Gateway is being weird, should never accept that message
        end
      end

      def parse_receipt(request)
        if (stream = request.env['rack.input'])
          raw_data = stream.read
        else
          raise ArgumentError, "Input stream required"
        end

        parsed_data = CGI::parse(raw_data)
        tid = parsed_data["REF"].first
        result = {:id => tid}
        state = parsed_data["STATE"].first
        ref = parsed_data["REF"].first
        raise InvalidReceiptError if ref.blank?
        raise InvalidReceiptError if state.blank?
        case state
          when "DELIVRD"
            result[:status] = :delivered
          when "UNDELIV"
            result[:status] = :in_progress
          when "EXPIRED"
            result[:status] = :failed
          when "FAILED"
            result[:status] = :failed
          when "BARRED"
            result[:status] = :failed
          when "BARREDT"
            result[:status] = :failed
          when "BARREDC"
            result[:status] = :failed
          when "BARREDA"
            result[:status] = :failed
          when "ZERO_BAL"
            result[:status] = :failed
          when "INV_NET"
            result[:status] = :failed
          else
            result[:status] = :unknown
        end
        result[:vendor_status] = parsed_data["STATE"].first
        result[:vendor_message] = parsed_data["DELIVERYTIME"].first
        result
      end

      private

        def post_data(message, recipient_number, sender_number)
          message.gsub!('😃', ':)')
          {
            "USER" => @user,
            "PW" => @password,
            "RCV" => number_to_msisdn(recipient_number),
            "SND" => sender_number || @default_sender_number,
            "TXT" => message.encode('iso-8859-1', CONVERSION_OPTIONS),
            "RCPREQ" => "Y" # get a unique reference value back
          }
        end
        def number_to_msisdn(number)
          if number =~ /^\+(.*)/
            return $1
          else
            return "#{@default_prefix}#{number}"
          end
        end
    end

  end
end
