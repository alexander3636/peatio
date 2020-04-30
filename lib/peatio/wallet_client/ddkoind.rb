# encoding: UTF-8
# frozen_string_literal: true

module WalletClient
  class Ddkoind < Base

    def initialize(*)
      super
      @json_rpc_endpoint = URI.parse(wallet.uri)
    end


    def create_address!(options = {})
	  secret = options.fetch(:secret) { json_rpc(:get, '/api/utils/generate-passphrase').fetch('data') }
	  secret.yield_self do |password|
	  { address: json_rpc(:post, '/api/accounts', { secret: password }).fetch('data').fetch('address'),
          secret:  password }
	  end
    end

    def load_balance!(address, currency, options = {})
      json_rpc(:get, "/api/accounts/#{address}/balance")
          .fetch('data')
          .yield_self { |amount| convert_from_base_unit(amount) }
    end

    def create_withdrawal!(issuer, recipient, amount, options = {})
      withdrawal_request(issuer, recipient, amount, options = {})
        .fetch('id')
        .yield_self { |txid| normalize_txid(txid) }
    end

    def get_txn_fee(issuer, recipient, amount, options = {})
      withdrawal_request(issuer, recipient, amount, options = {})
        .fetch('fee')
    end

    def inspect_address!(address)
      { address:  normalize_address(address),
        is_valid: true }
    end

    def normalize_address(address)
      address
    end

    def normalize_txid(txid)
      txid
    end


    protected

    def connection
      Faraday.new(@json_rpc_endpoint).tap do |connection|
        unless @json_rpc_endpoint.user.blank?
          connection.basic_auth(@json_rpc_endpoint.user, @json_rpc_endpoint.password)
        end
      end
    end
    memoize :connection

    def json_rpc(method, path, params = [])
      if method == :get

        response = connection.get \
          path,
          params,
          {'Content-Type'=> 'application/json', 'Accept' => 'application/json'}
      else
        response = connection.post \
          path,
          params.to_json,
          {'Content-Type'=> 'application/json', 'Accept' => 'application/json'}
      end

      response.assert_success!
      response = JSON.parse(response.body)
      response['error'].tap { |error| raise Error, error.inspect if error }
      response
    end

    def withdrawal_request(issuer, recipient, amount, options = {})
      params = { destinations: [{ address: recipient[:address], amount: amount }] }
      json_rpc(:post, '/api/transactions', params).fetch('data')
    end
  end
end

