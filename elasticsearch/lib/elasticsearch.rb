# Licensed to Elasticsearch B.V. under one or more contributor
# license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright
# ownership. Elasticsearch B.V. licenses this file to you under
# the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

require 'elasticsearch/version'
require 'elasticsearch/transport'
require 'elasticsearch/api'

module Elasticsearch
  class Client
    include Elasticsearch::API
    SECURITY_PRIVILEGES_VALIDATION_WARNING = 'The client is unable to verify that the server is Elasticsearch due to security privileges on the server side.'.freeze
    YOU_KNOW_FOR_SEARCH = 'You know, for Search'.freeze

    def initialize(arguments = {}, &block)
      @verified = false
      @transport = Elasticsearch::Transport::Client.new(arguments, &block)
    end

    def method_missing(name, *args, &block)
      verify_elasticsearch unless @verified
      if methods.include?(name)
        super
      elsif @verified
        @transport.send(name, *args, &block)
      else
        raise Elasticsearch::NotElasticsearchError
      end
    end

    def verify_elasticsearch
      begin
        response = @transport.perform_request('GET', '/')
      rescue Elasticsearch::Transport::Transport::Errors::Unauthorized,
             Elasticsearch::Transport::Transport::Errors::Forbidden
        @verified = true
        warn(SECURITY_PRIVILEGES_VALIDATION_WARNING)
        return
      end

      verify_with_version_or_header(response)
    end

    def verify_with_version_or_header(response)
      version = response.body.dig('version', 'number')
      raise Elasticsearch::NotElasticsearchError if version.nil? || version < '6.0.0'

      if version == '7.x-SNAPSHOT' || Gem::Version.new(version) >= Gem::Version.new('7.14-SNAPSHOT')
        raise Elasticsearch::NotElasticsearchError unless response.headers['x-elastic-product'] == 'Elasticsearch'

        @verified = true
      elsif Gem::Version.new(version) > Gem::Version.new('6.0.0') &&
         Gem::Version.new(version) < Gem::Version.new('7.0.0')
        raise Elasticsearch::NotElasticsearchError unless
          response.body.dig('version', 'tagline') == YOU_KNOW_FOR_SEARCH

        @verified = true
      elsif Gem::Version.new(version) >= Gem::Version.new('7.0.0') &&
            Gem::Version.new(version) < Gem::Version.new('7.14-SNAPSHOT')
        raise Elasticsearch::NotElasticsearchError unless
          response.body.dig('version', 'tagline') == YOU_KNOW_FOR_SEARCH &&
          response.body.dig('version', 'build_flavor') == 'default'

        @verified = true
      end
    end
  end

  class NotElasticsearchError < StandardError
    def initialize
      super('The client noticed that the server is not Elasticsearch and we do not support this unknown product.')
    end
  end
end

module Elastic
  # If the version is X.X.X.pre/alpha/beta, use X.X.Xp for the meta-header:
  def self.client_meta_version
    regexp = /^([0-9]+\.[0-9]+\.[0-9]+)\.?([a-z0-9.-]+)?$/
    match = Elasticsearch::VERSION.match(regexp)
    return "#{match[1]}p" if match[2]

    Elasticsearch::VERSION
  end

  # Constant for elasticsearch-transport meta-header
  ELASTICSEARCH_SERVICE_VERSION = [:es, client_meta_version].freeze
end
