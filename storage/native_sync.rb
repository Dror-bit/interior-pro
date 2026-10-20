require_relative 'adapters'
module InteriorPro
  module Storage
    remove_const(:USE_NATIVE_SYNC) if const_defined?(:USE_NATIVE_SYNC,false)
    USE_NATIVE_SYNC=true
    class NativeObserver < Sketchup::ModelObserver
      def onTransactionCommit(model)
        return if @busy || !Storage::USE_NATIVE_SYNC
        begin
          @busy=true
          dict=model.attribute_dictionary(Cabinetry::ModelStore::DICTIONARY,false)
          if dict
            dict.keys.each do |key|
              domain,id=key.split(':',2)
              next unless Cabinetry.domains_for_tool('storage').include?(domain)
              next if domain=='wardrobe' && !Storage::USE_WARDROBE_PRODUCTS
              service=Storage.service_for(model,domain,id)
              error=service.sync_native!
              Storage.report_error(error) if error
            end
          end
          Storage.refresh
        rescue StandardError=>e
          Storage.report_error(e.message)
        ensure
          @busy=false
        end
      end
      def onTransactionUndo(model);Storage.refresh;end
      def onTransactionRedo(model);Storage.refresh;end
    end
    def self.watch(model)
      @watchers||={}
      # Opening a file can reuse the Ruby Model wrapper while discarding its
      # observers. Reattach even when this wrapper is already in the registry.
      previous=@watchers.delete(model)
      model.remove_observer(previous) if previous
      observer=NativeObserver.new
      model.add_observer(observer)
      @watchers[model]=observer
    end
    class AppObserver < Sketchup::AppObserver
      def onNewModel(model);Storage.watch(model);end
      def onOpenModel(model);Storage.watch(model);end
      def onQuit;Storage.unwatch_all;end
    end
    def self.unwatch_all
      (@watchers || {}).each { |model,observer|model.remove_observer(observer) rescue nil }
      @watchers={}
    end
    def self.install_observers
      return unless USE_NATIVE_SYNC
      watch(Sketchup.active_model)
      unless @app_observer
        @app_observer=AppObserver.new
        Sketchup.add_observer(@app_observer)
      end
    end
  end
end
