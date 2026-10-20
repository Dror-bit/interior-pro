require_relative 'core'

module InteriorPro
  module Cabinetry
    # Caller owns ONE native operation for document + geometry + hosted fixtures.
    # Explicit model injection: never borrows KitchenLab's active model/settings.
    class ModelStore
      DICTIONARY = 'InteriorPro::Cabinetry' unless const_defined?(:DICTIONARY,false)
      def initialize(model)
        @model=model
      end

      def key(domain, assembly_id)
        "#{Cabinetry.domain!(domain)}:#{Cabinetry.identifier!(assembly_id)}"
      end

      def read(domain:, assembly_id:)
        raw=@model.get_attribute(DICTIONARY,key(domain,assembly_id))
        return nil if raw.nil?
        doc=Cabinetry.validate(JSON.parse(raw))
        raise ArgumentError, 'Stored identity mismatch' unless doc['domain']==domain && doc['assembly_id']==assembly_id
        doc
      end

      def write(document, expected_revision:)
        doc=Cabinetry.validate(document)
        old=read(domain:doc['domain'],assembly_id:doc['assembly_id'])
        actual=old && old['revision']
        raise ArgumentError, 'Design changed; refresh first' unless actual==expected_revision
        return doc if old==doc
        target=old ? old['revision']+1 : 0
        raise ArgumentError, 'Invalid next revision' unless doc['revision']==target
        @model.set_attribute(DICTIONARY,key(doc['domain'],doc['assembly_id']),JSON.generate(doc))
        doc
      end

      # Generated geometry ownership is independent from source documents.
      def stamp(group, document, cabinet_id, role:'cabinet')
        d=Cabinetry.validate(document)
        raise ArgumentError, 'Cabinet not in this assembly' unless d['cabinets'].any? { |c|c['id']==cabinet_id }
        Cabinetry.identifier!(role)
        {'domain'=>d['domain'],'assembly_id'=>d['assembly_id'],'cabinet_id'=>cabinet_id,'role'=>role}.each do |k,v|
          group.set_attribute(DICTIONARY,k,v)
        end
        group
      end
    end
  end
end
