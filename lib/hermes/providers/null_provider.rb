module Hermes
  module Providers

    # Provider which does not do anything.
    class NullProvider

      def initialize(options = {})
      end

      def send_message!(options)
        (Time.now.to_i+([*1..10000].sample)).to_s
      end

      def test!
        true
      end

      def parse_receipt(request)
        {}
      end

    end

  end
end