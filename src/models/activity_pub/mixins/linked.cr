require "uri"

require "../../../framework/model"
require "../../../framework/open"
require "../../../framework/signature"
require "../../../framework/constants"

module Ktistec
  module Model
    module Linked
      def origin
        uri = URI.parse(iri)
        "#{uri.scheme}://#{uri.host}"
      end

      def uid
        URI.parse(iri).path.split("/").last
      end

      def local?
        iri.starts_with?(Ktistec.host)
      end

      def cached?
        !local?
      end

      macro included
        @[Persistent]
        property iri : String { "" }
        validates(iri) { unique_absolute_uri?(iri) }

        private def unique_absolute_uri?(iri)
          if iri.blank?
            "must be present"
          elsif !URI.parse(iri).absolute?
            "must be an absolute URI: #{iri}"
          elsif (instance = self.class.find?(iri)) && instance.id != self.id
            "must be unique: #{iri}"
          end
        end

        def self.find(_iri iri : String?)
          find(iri: iri)
        end

        def self.find?(_iri iri : String?)
          find?(iri: iri)
        end

        def self.dereference?(key_pair, iri, ignore_cached = false) : self?
          unless !ignore_cached && (instance = self.find?(iri))
            unless iri.starts_with?(Ktistec.host)
              headers = Ktistec::Signature.sign(key_pair, iri, method: :get)
              headers["Accept"] = Ktistec::Constants::ACCEPT_HEADER
              Ktistec::Open.open?(iri, headers) do |response|
                instance = self.from_json_ld?(response.body)
              end
            end
          end
          instance
        end

        macro finished
          {% verbatim do %}
            {% for type in @type.all_subclasses << @type %}
              {% for method in type.methods.select { |d| d.name.starts_with?("_association_") } %}
                {% if method.body.first == :belongs_to %}
                  {% name = method.name[13..-1] %}
                  class ::{{type}}
                    def {{name}}?(key_pair, *, dereference = false, ignore_cached = false)
                      {{name}} = self.{{name}}?
                      unless (!ignore_cached && {{name}}) || ({{name}} && {{name}}.changed?)
                        if ({{name}}_iri = self.{{name}}_iri) && dereference
                          unless {{name}}_iri.starts_with?(Ktistec.host)
                            {% for union_type in method.body[1].id.split(" | ").map(&.id) %}
                              headers = Ktistec::Signature.sign(key_pair, {{name}}_iri, method: :get)
                              headers["Accept"] = Ktistec::Constants::ACCEPT_HEADER
                              Ktistec::Open.open?({{name}}_iri, headers) do |response|
                                if ({{name}} = {{union_type}}.from_json_ld?(response.body))
                                  return self.{{name}} = {{name}}
                                end
                              end
                            {% end %}
                          end
                        end
                      end
                      {{name}}
                    end
                  end
                {% end %}
              {% end %}
            {% end %}
          {% end %}
        end
      end
    end
  end
end

# :nodoc:
module Linked
end
