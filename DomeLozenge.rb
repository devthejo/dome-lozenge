require 'sketchup.rb'
require 'extensions.rb'

module Takion
  module DomeLozenge
    dome_extension = SketchupExtension.new('Dome Lozenge', 'DomeLozenge/core.rb')
    dome_extension.version = '1.2.2'
    dome_extension.copyright = '2018'
    dome_extension.description = 'Dome Lozenge Creator'
    dome_extension.creator = 'Jo Takion <jo@redcat.ninja>'
    Sketchup.register_extension(dome_extension, true)
  end
end
