# encoding: UTF-8
# frozen_string_literal: true

module WalletServices
  class Rippled < Peatio::WalletService::Abstract

    include Peatio::WalletService::Helpers

    def client
      @client ||= WalletClient::Rippled.new(@wallet)
    end

    def create_address!(options = {})
      client.create_address!(options.merge(
        address: "#{@wallet.address}?dt=#{generate_destination_tag}",
        secret: @wallet.settings['secret']
      ))
    end

    def collect_deposit!(deposit, options={})
      pa = deposit.account.payment_address
      spread_hash = spread_deposit(deposit, client)
      spread_hash.map do |address, amount|
        client.create_withdrawal!(
          { address: pa.address, secret: pa.secret },
          { address: address },
          amount,
          options
        )
      end
    end

    def build_withdrawal!(withdraw, options = {})
      client.create_withdrawal!(
        { address: @wallet.address, secret: @wallet.secret },
        { address: withdraw.rid },
        withdraw.amount,
        options
      )
    end

    def load_balance(address, currency)
      client.load_balance!(address, currency)
    end

    private

    def generate_destination_tag
      begin
        # Reserve destination 1 for system purpose
        tag = SecureRandom.random_number(10**9) + 2
      end while PaymentAddress.where(currency_id: :xrp)
                              .where('address LIKE ?', "%dt=#{tag}")
                              .any?
      tag
    end
  end
end
