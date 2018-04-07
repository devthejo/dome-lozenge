module Takion
  module DomeLozenge

    require 'sketchup.rb'
    require 'extensions.rb'
    require 'langhandler.rb'
    
    LH = LanguageHandler.new('DomeLozenge.strings')
    if !LH.respond_to?(:[])
      def LH.[](key)
        GetString(key)
      end
    end
  
    dome_extension = SketchupExtension.new('Dome Lozenge', 'DomeLozenge/main.rb')
    dome_extension.version = '1.3.1'
    dome_extension.copyright = '2018'
    dome_extension.description = 'Dome Lozenge Creator'
    dome_extension.creator = 'Jo Takion <jo@redcat.ninja>'
    Sketchup.register_extension(dome_extension, true)
  end
end
