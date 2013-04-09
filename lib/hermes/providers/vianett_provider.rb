require 'active_support/core_ext/hash/keys'

module Hermes
  module Providers

    class VianettProvider

      # Thrown if gateway fails.
      class InternalError < GatewayError
        def initialize(message, status_code, refno)
          super("#{message} (#{status_code})")
          @message, @status_code, @refno = message, status_code, refno
        end
        attr_reader :message, :status_code, :refno
      end

      # Thrown when the API rejects a message, eg. due to invalid data.
      class MessageRejectedError < ::Hermes::MessageRejectedError
        def initialize(message, status_code, refno)
          super("#{message} (#{status_code})")
          @message, @status_code, @refno = message, status_code, refno
        end
        attr_reader :message, :status_code, :refno
      end

      class CouldNotFetchMMSDataError < GatewayError; end

      attr_reader :user_name
      attr_reader :password
      attr_reader :default_sender

      def initialize(options = {})
        options.assert_valid_keys(
          :username, :password, :default_sender)

        @username = options[:username]
        raise ConfigurationError, "'username' must be specified" unless @username

        @password = options[:password]
        raise ConfigurationError, "'password' must be specified" unless @password

        if (default_sender = options[:default_sender])
          default_sender.symbolize_keys!
          if default_sender[:number]
            @default_sender = {
              number: default_sender[:number],
              type: default_sender[:type].try(:to_sym) || :msisdn
            }.freeze
          end
        end
      end

      def send_message!(options)
        options.assert_valid_keys(
          :receipt_url, :sender_number, :recipient_number, :text)

        id = generate_id
        params = build_params(id, options)
        with_retrying do
          logger.info "[Vianett] Posting outgoing: #{params.inspect}"
          check_response(
            Excon.new(BASE_URI).post(
              path: OUTGOING_PATH,
              query: params))
        end
        id
      end

      # Test whether provider is functional. Returns true or false.
      def test!
        begin
          send_message!(recipient_number: '_', text: '')
        rescue Excon::Errors::Error
          false
        rescue MessageRejectedError
          true
        else
          false  # Gateway is being weird, should never accept that message
        end
      end

      def parse_receipt(request)
        params = request.params.symbolize_keys

        result = {}
        case params[:requesttype]
          when 'notificationstatus'
            result[:vendor_status] = params[:Status].to_s.downcase
            result[:vendor_message] = params[:StatusDescription]
            case params[:vendor_status]
              when 'acceptd', 'bufferd'
                result[:status] = :sent
              when 'deliverd'
                result[:status] = :delivered
              else
                raise InvalidReceiptError
            end
          when 'mtstatus'
            result[:vendor_status] = params[:ErrorCode]
            result[:vendor_message] = params[:ErrorDescription]
            if params[:msgok] =~ /true/i
              result[:status] = :delivered
            else
              result[:status] = :failed
            end
          else
            raise InvalidReceiptError
        end
        result[:id] = params[:refno] if params[:refno]
        result
      end

      def ack_receipt(result, controller)
        id = result[:id]
        controller.halt 200,
          "<?xml version='1.0'?>" \
          "<ack refno='#{id}' errorcode='0'></ack>"
      end

      def parse_message(request)
        params = request.params.symbolize_keys

        raise ArgumentError, "Invalid message" unless
          params[:sourceaddr].present? and
          params[:destinationaddr].present? and
          params[:refno].present?

        result = {
          id: params[:refno],
          sender_number: params[:sourceaddr],
          recipient_number: params[:destinationaddr],
          vendor: {
            refno: params[:refno],
            operator: params[:operator],
            retry_count: params[:retrycount].to_i,
            prefix: params[:prefix]
          }
        }
        if params[:mmsdata].present?
          result[:type] = :mms
          result[:binary] = {
            content_type: 'application/zip',
            value: Base64.decode64(params[:mmsdata]).force_encoding('binary')
          }
        elsif params[:mmsurl].present?
          result[:type] = :mms
          result[:binary] = fetch_mms_url(params[:mmsurl])
        elsif params[:message].present? or params[:prefix].present?
          result[:type] = :sms
          result[:text] = [params[:prefix], params[:message]].select(&:present?).join(' ')
        else
          raise ArgumentError, "Missing message content"
        end
        result
      end

      def ack_message(message, controller)
        refno = result[:vendor][:refno]
        controller.halt 200,
          "<?xml version='1.0'?>" \
          "<ack refno='#{refno}' errorcode='0'></ack>"
      end

      private

        BASE_URI = 'https://smsc.vianett.no/'.freeze
        OUTGOING_PATH = '/V3/CPA/MT/MT.ashx'.freeze

        def logger
          LOGGER
        end

        def fetch_mms_url(url)
          visited = Set.new
          loop do
            with_retrying do
              response = Excon.get(url)
              if response.status == 200
                return {
                  value: response.body,
                  content_type: response.headers['Content-Type']
                }
              elsif response.status == 301 or response.status == 302
                location = URI.parse(response.headers['Location'])
                if visited.add?(location)
                  url = location.to_s
                else
                  raise CouldNotFetchMMSDataError, "Redirect loop fetching #{url}"
                end
              else
                raise CouldNotFetchMMSDataError, "Error #{response.status} getting MMS data from #{url}"
              end
            end
          end
        end

        def with_retrying(&block)
          retries_left = 10
          begin
            yield
          rescue Excon::Errors::SocketError => e
            if retries_left > 0
              logger.error("Failed with exception, will retry: #{e}")
              sleep(0.5)
              retry
            else
              raise
            end
          end
        end

        def check_response(response)
          unless response.body.present?
            raise InvalidResponseError, "Server returned empty body with status #{response.status}"
          end
          begin
            doc = Nokogiri::XML(response.body)
          rescue Nokogiri::XML::SyntaxError => e
            raise InvalidResponseError, "Invalid response from gateway: #{response.body.inspect}"
          else
            if (ack = doc.xpath('/ack').first)
              case ack['errorcode']
                when '200'
                  # This means success
                when '5000'
                  raise InternalError.new(
                    ack.content.present? ? ack.content : "Unknown error",
                    ack['errorcode'].to_i, ack['refno'])
                else
                  raise MessageRejectedError.new(
                    ack.content.present? ? ack.content : "Unknown error",
                    ack['errorcode'].to_i, ack['refno'])
              end
            else
              raise InvalidResponseError, "Server returned invalid body: #{response.body.inspect}"
            end
          end
        end

        def build_params(id, options)
          [:recipient_number, :text].each do |key|
            unless options[key].present?
              raise ArgumentError, "Missing or empty value for #{key}"
            end
          end

          params = {
            msgid: id,
            username: @username,
            password: @password,
            Tel: number_to_msisdn(options[:recipient_number]),
            msg: options[:text].encode('utf-8')
          }

          if (sender = options[:sender_number]) && sender.present?
            params[:senderaddress] = sender
            params[:senderaddresstype] = sender =~ /\A\s*\+?[0-9\s]+\s*\z/ ? 1 : 5
          elsif (default_sender = @default_sender)
            case default_sender[:type]
              when :short_code
                params[:senderaddress] = default_sender[:number]
                params[:senderaddresstype] = 2
              when :alphanumeric
                params[:senderaddress] = default_sender[:number]
                params[:senderaddresstype] = 5
              when :msisdn
                params[:senderaddress] = default_sender[:number]
                params[:senderaddresstype] = 1
            end
          end

          params
        end

        def number_to_msisdn(number)
          if number =~ /^\+(.*)/
            $1
          else
            number
          end
        end

        def generate_id
          id = Time.now.strftime('%Y%m%d%H%M%S')
          id << SecureRandom.random_number(999).to_s
        end

    end

  end
end