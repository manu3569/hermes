module Hermes
  class Message < ActiveRecord::Base

    VALID_STATUSES = [
      :failed,
      :in_progress,
      :delivered,
      :unknown
    ].freeze

    validates :realm, :presence => {}
    validates :vendor_id, :presence => {}
    validates :status, :inclusion => {:in => VALID_STATUSES}

    after_update :notify_callback_url

    class Statistics
      def initialize
        @failed_count, @in_progress_count, @delivered_count, @unknown_count = 0, 0, 0, 0
      end

      attr_writer :failed_count
      attr_writer :in_progress_count
      attr_writer :delivered_count
      attr_writer :unknown_count

      def [](key)
        instance_variable_get("@#{key}")
      end
    end

    class << self
      def statistics(options = {})
        result = Statistics.new
        where = arel_table['status'].not_eq(nil)
        if (realm = options[:realm])
          where = where.and(arel_table['realm'].eq(realm.to_s))
        end
        if (kind = options[:kind])
          where = where.and(arel_table['kind'].eq(kind.to_s))
        end
        connection.select_all(
          arel_table.project("status, count(*)").where(where).
            group(arel_table['status']).to_sql
        ).each do |row|
          status, count = row['status'], row['count'].to_i
          result.send("#{status}_count=", count)
        end
        result
      end
    end

    def status=(value)
      if value
        value = value.to_sym if value.respond_to?(:to_sym)
        super(value)
      end
    end

    private

      # TODO: Schedule asynchronously using AMQP
      def notify_callback_url
        if self.callback_url and status_changed?
          uri = URI.parse(self.callback_url)
          uri.query << '&' if uri.query
          uri.query ||= ''
          uri.query << "status=#{self.status}"
          logger.info("Notifying callback #{uri}")
          begin
            Timeout.timeout(10) do
              Excon.post(uri.to_s)
            end
          rescue Exception => e
            logger.error("Callback failed: #{uri}: #{e.class}: #{e.message}")
          end
        end
        true
      end

  end
end