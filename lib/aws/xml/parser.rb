# Copyright 2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

require 'multi_xml'
require 'time'
require 'base64'

module Aws
  module Xml
    # @api private
    class Parser

      include Seahorse::Model::Shapes

      # @param [Seahorse::Model::Shapes::Shape] rules
      def initialize(rules)
        @rules = rules
      end

      # @param [String<xml>] xml
      # @param [Hash] target (nil)
      # @return [Hash]
      def parse(xml, target = nil)
        target ||= Structure.new(@rules.members.keys)
        structure(@rules, MultiXml.parse(xml).values.first || {}, target)
      end

      # @param [Seahorse::Model::Shapes::OutputShape] rules
      # @param [String<xml>] xml
      # @param [Hash] target (nil)
      # @return [Hash]
      def self.parse(rules, xml, target = nil)
        Parser.new(rules.payload_member).parse(xml, target)
      end

      private

      def structure(shape, hash, target = nil)
        target ||= Structure.new(shape.members.keys)
        shape.members.each do |member_name, member_shape|
          key = member_shape.serialized_name
          target[member_name] = member(member_shape, hash[key])
        end
        target
      end

      def list(shape, values)
        member_shape = shape.members
        unless flat?(shape)
          values = values[member_shape.serialized_name || 'member']
        end
        values = [values] unless values.is_a?(Array)
        values.map { |value| member(member_shape, value) }
      end

      def map(shape, entries)
        key_shape = shape.keys
        value_shape = shape.members
        data = {}
        entries = entries['entry'] unless flat?(shape)
        entries = [entries] unless entries.is_a?(Array)
        entries.each do |entry|
          key = entry[key_shape.serialized_name || 'key']
          value = entry[value_shape.serialized_name || 'value']
          data[member(key_shape, key)] = member(value_shape, value)
        end
        data
      end

      def member(shape, raw)
        if raw.nil?
          case shape
          when StructureShape, MapShape then {}
          when ListShape then []
          else nil
          end
        else
          case shape
          when StructureShape then structure(shape, raw)
          when ListShape then list(shape, raw)
          when MapShape then map(shape, raw)
          when BooleanShape then raw == 'true'
          when IntegerShape then raw.to_i
          when FloatShape then raw.to_f
          when TimestampShape then timestamp(raw)
          when BlobShape then Base64.decode64(raw)
          else raw
          end
        end
      end

      def timestamp(raw)
        case raw
        when nil then nil
        when /^\d+$/ then Time.at(raw.to_i)
        else
          begin
            Time.parse(raw)
          rescue ArgumentError
            raise "unhandled timestamp format `#{raw}'"
          end
        end
      end

      def flat?(shape)
        FlatListShape === shape || FlatMapShape === shape
      end

    end
  end
end
