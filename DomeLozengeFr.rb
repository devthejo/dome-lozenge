require 'sketchup.rb'
require 'extensions.rb'

dome_extension = SketchupExtension.new('Dome Lozenge FR', 'DomeLozengeFr/core.rb')
dome_extension.version = '1.2.2'
dome_extension.copyright = '2018'
dome_extension.description = 'Dome Lozenge Creator FR'
dome_extension.creator = 'Jo Takion <jo@redcat.ninja>'
Sketchup.register_extension(dome_extension, true)
