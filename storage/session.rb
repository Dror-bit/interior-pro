require_relative 'adapters'
module InteriorPro
  module Storage
    # Each product mode retains its own assembly selection and source namespace.
    class Session
      attr_reader :model,:domain,:assembly_id
      def initialize(model)
        @model=model;@assemblies={};switch('laundry','main')
      end
      def switch(domain,assembly_id=nil)
        raise ArgumentError,'Unknown Storage mode' unless Cabinetry.domains_for_tool('storage').include?(domain)
        id=Cabinetry.identifier!(assembly_id || @assemblies[domain] || 'main')
        doc=Cabinetry::ModelStore.new(@model).read(domain:domain,assembly_id:id)
        @domain=domain;@assembly_id=id;@assemblies[domain]=id
        doc || Cabinetry.create(domain:domain,assembly_id:id)
      end
      def document
        Cabinetry::ModelStore.new(@model).read(domain:@domain,assembly_id:@assembly_id) || Cabinetry.create(domain:@domain,assembly_id:@assembly_id)
      end
      def service
        Storage.service_for(@model,@domain,@assembly_id)
      end
      def editable?;@domain=='laundry' || Storage::USE_WARDROBE_PRODUCTS;end
      def product_domain;@domain=='wardrobe' ? WardrobeDomain : Laundry::Domain;end
      def check_request!(p)
        raise ArgumentError,'Product mode or assembly changed; refresh first' unless p['domain']==@domain && p['assembly_id']==@assembly_id
        raise ArgumentError,'Design changed; refresh first' unless p['revision']==document['revision']
      end
    end
  end
end
