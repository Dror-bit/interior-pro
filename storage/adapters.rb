require_relative 'wardrobe_service'
module InteriorPro
  module Storage
    remove_const(:USE_WARDROBE_PRODUCTS) if const_defined?(:USE_WARDROBE_PRODUCTS,false)
    USE_WARDROBE_PRODUCTS=true
    def self.service_for(model,domain,assembly_id)
      raise ArgumentError,'Unknown Storage domain' unless Cabinetry.domains_for_tool('storage').include?(domain)
      if domain=='wardrobe'
        raise ArgumentError,'Wardrobe products are disabled' unless USE_WARDROBE_PRODUCTS
        WardrobeService.new(model,assembly_id)
      else
        Laundry::Service.new(model,assembly_id)
      end
    end
  end
end
