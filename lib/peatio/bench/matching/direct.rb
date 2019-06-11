# frozen_string_literal: true

# TODO: Add Bench::Error and better errors processing.
# TODO: Add Bench::Report and extract all metrics to it.
module Bench
  module Matching
    class Direct
      include Helpers

      def initialize(config)
        @config = config

        @injector = Injectors.initialize_injector(@config[:orders])
        @currencies = Currency.where(id: @config[:currencies].split(',').map(&:squish).reject(&:blank?))
        @matching = Workers::AMQP::Matching.new
        # TODO: Print errors in the end of benchmark and include them into report.
        @errors = []
      end

      def run!
        Kernel.puts "Creating members ..."
        @members = Factories.create_list(:member, @config[:traders])

        Kernel.puts "Depositing funds ..."
        @members.map(&method(:become_billionaire))

        Kernel.puts "Generating orders by injector and saving them in db..."
        # TODO: Add orders generation progress bar.
        @injector.generate!(@members)

        @orders_number = @injector.size

        @matching_started_at = Time.now

        process_messages

        @matching_finished_at = Time.now
      end

      def process_messages
        loop do
          order = @injector.pop
          if order.present?
            order.fix_number_precision
            order.locked = order.origin_locked = order.compute_locked
            order.hold_account!.lock_funds(order.locked)
            order.save!
          end
          if @injector.size == 0
            10.times { p "-" }
            sleep @orders_number/10 + 1
            pp "Market Orders: #{Order.where(ord_type: :market).count} "
            min_ask = OrderAsk.where(state: :wait).pluck(:price).compact.min
            max_bid = OrderBid.where(state: :wait).pluck(:price).compact.max
            if min_ask.present? && max_bid.present? && max_bid >= min_ask
              10.times { p "-" }
              p 'Wrong mathing behaviour'
              pp " Min ASK #{min_ask}"
              pp " Max BID #{max_bid}"
              10.times { p "-" }
            end
            break
          end
          @matching.process({action: 'submit', order: order.to_matching_attributes}, 'metadata', 'delivery_info')
        rescue StandardError => e
          Kernel.puts e
          @errors << e
        end
      end

      # TODO: Add more useful metrics to result.
      def result
        @result ||=
        begin
          matching_ops = @orders_number / (@matching_finished_at - @matching_started_at)

          # TODO: Deal with calling iso8601(6) everywhere.
          { config: @config,
            matching: {
              started_at:  @matching_started_at.iso8601(6),
              finished_at: @matching_finished_at.iso8601(6),
              operations:  @orders_number,
              ops:         matching_ops
            }
          }
        end
      end

      def save_report
        report_path = Rails.root.join(@config[:report_path])
        FileUtils.mkpath(report_path)
        report_name = "#{self.class.parent.name.demodulize.downcase}-"\
                      "#{self.class.name.humanize.demodulize}-#{@config[:orders][:injector]}-"\
                      "#{@config[:orders][:number]}-#{@matching_started_at.iso8601}.yml"
        File.open(report_path.join(report_name), 'w') do |f|
          f.puts YAML.dump(result.deep_stringify_keys)
        end
      end
    end
  end
end
