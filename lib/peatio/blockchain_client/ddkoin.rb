# encoding: UTF-8
# frozen_string_literal: true

module BlockchainClient
  class Ddkoin < Base
    def initialize(*)
      super
      @json_rpc_call_id  = 0
      @json_rpc_endpoint = URI.parse(blockchain.server)
    end

    def endpoint
      @json_rpc_endpoint
    end

    def latest_block_number
      Rails.cache.fetch "latest_#{self.class.name.underscore}_block_number", expires_in: 5.seconds do
        json_rpc(:get, '/api/blocks/last').fetch('data').fetch('height')
      end
    end

    def get_block(block_hash)
      params = {"limit":250, "offset":0, "filter": {"block_id": block_hash, "type":10}}
	  json_rpc(:post, '/api/transactions/getMany', params).fetch('data')
    end

    def get_block_hash(height)
      current_block   = height || 0
	  params = {"jsonrpc":"1.0","id":"0","limit":100,"offset":0, "filter": {"height": current_block}}
      json_rpc(:post, '/api/blocks/getMany', params).fetch('data').fetch('blocks')[0].fetch('id')
    end


    def to_address(tx)
      normalize_address(tx.fetch('asset').fetch('recipientAddress'))
    end

    def build_transaction(tx, current_block, address)
      entries = tx.fetch('asset').map.with_index do |item, index|

        { amount:  convert_from_base_unit(item.fetch('amount'), currency),
          address: normalize_address(item.fetch("recipientAddress")),
          txout:   index }
      end

      { id:            normalize_txid(tx.fetch('id')),
        block_number:  current_block,
        entries:       entries
      }
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
  end
end
