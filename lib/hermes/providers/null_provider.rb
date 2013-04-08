module Hermes
  module Providers

    # Provider which does not do anything.
    class NullProvider

      def initialize(options = {})
      end

      def send_message!(options)
        Time.now.to_i.to_s
      end

      def test!
        true
      end

      def parse_receipt(url, raw_data, params = nil)
        {}
      end

    end

  end
end