#https://github.com/takion/dome-lozenge jo@redcat.ninja

require 'sketchup.rb'

module Takion
  module DomeLozenge
		# @takion_%plugin%['%?_(.*)%'] -> ?:
		# N -> Nombre				(Integer)	
		# M -> Nombre Matriciel		(Integer)	
		# L -> Longueur				(Float.mm)	
		# T -> Type Texte			(String)			-> depuis paramètre selectioné dans une liste

		class DomeLozenge
			
			def self.generation
				self.new
			end
			def initialize
				#<INITIALISATION>
				@mo = Sketchup.active_model
				@u_inch = 0.0254 #Ne pas modifier
				#</INITIALISATION>
				#<DIALOG>
				#<default>
				config = [	
					# ['T_ShowMatrix','No','MatrixView',"Yes|No"],
					['N_Cotes',16,'Sides of rotation around the axis'],
					['N_Niveaux',7,'Vertical Layer'],
					['L_Diametre',8000.mm,'Ground diameter'],
					['L_Hauteur',2905.7.mm,'Height at the top'],
					['N_MIRROR',0,'Fraction Mirroir'],
					['T_Modelisation','Faces','Modelisation',"Squelette|Faces"],
					['T_Ground','No','Ground',"Yes|No"],
					['T_Rapport','Full','Rapport',"Light|Full|None"],
					['T_Tuiles2D','No','2D Tiles',"No|Yes"],
					['L_SQUARES',0.mm,'Raising from ground'],
					['L_RayonConnecteurs',160.mm,'Radius of Connectors'],
					['L_Tuilage',50.mm,'Tiles Overlapping'],
					['L_Diametre_Arretes',20.mm,'Edges Diameter'],
					['L_EPAISSEUR',0.mm,'Thickness'],
					['L_VORTEX',0.mm,'Vortex diameter'],
					['RVB_BACK_FACES','green','External faces color'],
					['RVB_BACK_SOL','green','External ground color'],
					['RVB_FACES','white','Internal faces color'],
					['RVB_SOL','white','Internal ground color'],
				]
				@takion_pcd = {} if not @takion_pcd
				0.upto(config.length-1){ |i|
					@takion_pcd[config[i][0]] = config[i][1] if not @takion_pcd[config[i][0]]
				}
				@takion_pcd['T_ShowMatrix'] = 'No'
				#</default>
				#<prompt>
				results = nil
				prompts = []
				defaults = []
				drops = []
				0.upto(config.length-1){ |i|
					defaults.push config[i][1]
					prompts.push config[i][2]
					if(config[i][3])
						drops.push config[i][3]
					else	
						drops.push nil
					end
				}
				begin
					results = UI.inputbox prompts,defaults,drops,'Paramètres du Dome Convex'
					return unless results
					0.upto(config.length-1){ |i|
						@takion_pcd[config[i][0]] = results[i]
					}
					#<validation>
					raise "Minimum vertical layer is 2"  if ( @takion_pcd['N_Niveaux'] < 2 )
					raise "Minimum 3 Sides of rotation around the axis"  if ( @takion_pcd['N_Cotes'] < 3 )
					raise "Non-zero Diameter required"  if ( @takion_pcd['L_Diametre'] <= 0 )
					raise "Non-zero Height required"  if ( @takion_pcd['L_Hauteur'] <= 0 )
					#</validation>
				rescue
					UI.messagebox $!.message
					retry
				end
				#</prompt>
				#</DIALOG>
				#<DEFINITION>
				Sketchup::set_status_text("Polygonal Convex Dome modelisation in progress ...")
				@mo.start_operation 'ConvexDome - Structure Processing'
				# @definition = @mo.definitions.add 'ConvexDome'
				# @entities = @definition.entities
				@group = @mo.active_entities.add_group
				@entities = @group.entities
				params = create_convexdome(@takion_pcd, 0, 0)
				create_convexdome(@takion_pcd, 0, 1)
				
				if(params['T_Ground']=='Yes')
					create_ground params
				end
				if(params['L_SQUARES']!=0)
					create_squares params
				end
				if(params['T_Tuiles2D']=='Yes')
					create_tiles params
				end
				if(params['T_Rapport']!='None')
					create_rapport params
				end
				if(params['T_ShowMatrix']=='Yes')
					show_matrix
				end
				
				@mo.commit_operation
				# @mo.place_component @definition
				#</DEFINITION>
			end
			
			def real_uniq(arr)
				arr = arr.sort
				narr = []
				v_l = nil
				for v in arr do
					if not v_l==v
						narr.push v
					end
					v_l = v
				end
				return narr
			end

			def check_distance a,b
				if (a && b)
					distance = a.distance b
					if (distance>0)
						return distance
					end
				end
				return 0
			end
			
			def aire_triangle_isocele base,cote
				return 0.5*(base*Math.sqrt((cote*cote)-((base*base)/4)))
			end
			def rayon_polygone_regulier n_cotes,segment_length
				return (segment_length/2.0)/(Math.sin((360.0/n_cotes)/(2.0*(180.0/Math::PI))))
			end
			def aire_polygone_regulier n_cotes,segment_length,radius
				if not radius
					radius = rayon_polygone_regulier n_cotes,segment_length
				end
				area = n_cotes*(0.5*(segment_length*Math.sqrt((radius*radius)-((segment_length*segment_length)/4.0))))*@u_inch*1000.0
				return area.inch
			end
			def create_convexdome(params,step=0,sens=0)
				#<MATRIX>
				#<initialisation>
				@tirants = []
				@arretes = []
				@ground_pts = []
				@levels_pts = []
				@matrix_pts = []
				@areas = []
				@faces = []
				@triangles = []
				@tiles_triangles = []
				@tiles_isosceles = []
				@hauteurs = []
				#</initialisation>
				#<create_logic>
				if(step==0)
					params['M_Cotes'] = (params['N_Cotes']*2).to_i
					params['M_Niveaux'] = (params['N_Niveaux']+1).to_i
					params['M_Hauteur'] = params['L_Hauteur'].to_l
					params['M_Rayon'] = (params['L_Diametre']/2).to_l
				end
				if(sens==1)
					params['M_Hauteur'] = params['L_Hauteur']*-1
				end
				@arretes_nb = (params['M_Cotes']*params['N_Niveaux'])-params['N_Cotes']
				@tirants_nb = (params['M_Cotes']*params['N_Niveaux'])/2
				@segments_nb = @arretes_nb+@tirants_nb
				@connecteurs_nb = (params['N_Cotes']*params['N_Niveaux'])+1
				#</create_logic>
				#<create_levels_points>
				cotes_rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, (Math::PI*2)/params['M_Cotes'])
				delta = Math::PI/(2*params['M_Niveaux'])
				for i in 0..params['M_Niveaux'] do
					angle = delta * i
					cosa = Math.cos(angle)
					sina = Math.sin(angle)
					level = [params['M_Rayon']*cosa, params['L_VORTEX'], params['M_Hauteur']*sina]
					if(step==2&&params['L_DOWN'])
						level[2]-=params['L_DOWN']
					end
					@levels_pts.push level
				end
				#</create_levels_points>
				#<create_revolution_points>
				0.upto(params['M_Cotes']+1){ |j|
					@matrix_pts[j] = []
					0.upto(params['M_Niveaux']){ |i|
						@levels_pts[i] = @levels_pts[i].transform(cotes_rotation)
						if j<params['M_Cotes']+1
							if (i>=1 && ( ((j%2==0) && (i%2==1)) || ((j%2==1) && (i%2==0)) ) )
								@matrix_pts[j].push @levels_pts[i-1]
							end
							
							if (i>=1 && ( ((j%2==0) && (i%2==0)) || ((j%2==1) && (i%2==1)) ) )
								@matrix_pts[j].push @levels_pts[i]
							end
						
						else
							@matrix_pts[j] = @matrix_pts[1]
						end
						
					}
					if j<params['M_Cotes']+1
						@matrix_pts[j].push @levels_pts[params['M_Niveaux']] #impair - dernier niveau supérieur
					end
				}
				#</create_revolution_points>
				#<create_ segments&&faces&&ground _points  &&  lines CREATION if squelette mode>
				
				0.upto(params['M_Cotes']+1){ |j|
					0.upto(params['M_Niveaux']){ |i|
						if ( (params['M_Niveaux']%2==0&&i>1)||(params['M_Niveaux']%2==1&&(i-1!=0||j%2==1)) ) #enlève le premier niveau de @tirants
							distanceT = check_distance @matrix_pts[j-2][i-1], @matrix_pts[j][i-1] #@tirants
							if(distanceT>0)
								if(params['T_Modelisation']=='Squelette'&&step==2)
									@entities.add_line @matrix_pts[j-2][i-1], @matrix_pts[j][i-1]
								end
								if (params['M_Niveaux']%2==1&&i==1) || (params['M_Niveaux']%2==0&&i==2&&j%2==1)
									@ground_pts.push @matrix_pts[j-2][i-1]
									@ground_pts.push @matrix_pts[j][i-1]
								end
								@hauteurs.push @matrix_pts[j-2][i-1][2]
								@tirants.push distanceT
								0.upto(params['M_Niveaux']){ |s| #arrêtes
									if (params['M_Niveaux']%2==0&&i-s>0)||(params['M_Niveaux']%2==1&&i!=1&&i-s!=0) #enlève le premier niveau d'arrêtes
										distanceA = check_distance @matrix_pts[j-1][i-s], @matrix_pts[j][i-s]
										if(distanceA>0)
											if(params['T_Modelisation']=='Squelette'&&step==2)
												@entities.add_line @matrix_pts[j-1][i-s], @matrix_pts[j][i-s]
											end
											if(sens==0||( sens==1&&i<params['N_MIRROR']+2 ))
												@faces.push( [ @matrix_pts[j-2][i-1], @matrix_pts[j][i-1], @matrix_pts[j-1][i-1] ] )
											end
											@arretes.push distanceA
										end
									end
								}
							end
						end
					}
				}
				@faces = @faces.uniq
				@ground_pts = @ground_pts.uniq
				@tirants = real_uniq( @tirants )
				@hauteurs = real_uniq( @hauteurs )
				@arretes = real_uniq( @arretes )
				@ground_segment_length = @tirants[params['N_Niveaux']-1]
				@tirants = @tirants.reverse
				@hauteurs = @hauteurs.reverse
				@arretes = @arretes.reverse
				@polygon_radius = rayon_polygone_regulier params['N_Cotes'].to_f,@ground_segment_length
				@ground_area = aire_polygone_regulier params['N_Cotes'].to_f,@ground_segment_length,@polygon_radius
				
				0.upto(params['N_Niveaux']-1){ |k|
					if(k==0)
						g_t = @tirants[k].to_f	
						g_a = @arretes[k].to_f
						@triangles.push( [g_t,g_a] )
						g_a+=params['L_Tuilage']*2
						g_t+=params['L_Tuilage']*2
						@tiles_triangles.push( [g_t,g_a] )
					else
						g_t = @tirants[k].to_f
						g_a = @arretes[k-1].to_f
						@triangles.push( [g_t,g_a] )
						g_t+=params['L_Tuilage']*2
						g_a+=params['L_Tuilage']*2
						@tiles_triangles.push( [g_t,g_a] )
						g_t = @tirants[k].to_f	
						g_a = @arretes[k].to_f
						@triangles.push( [g_t,g_a] )
						g_t+=params['L_Tuilage']*2
						g_a+=params['L_Tuilage']*2
						@tiles_triangles.push( [g_t,g_a] )
					end
				}
				#</create_ segments&&faces&&ground&&triangles&&tiles_triangles _points>
				#</MATRIX>
				if(step==0)
					params['M_Rayon'] = (params['M_Rayon']/@polygon_radius)*params['M_Rayon']
					top_h = @matrix_pts[0][@matrix_pts[0].length-1][2]
					base_h = @matrix_pts[0][0][2]
					if(base_h==0)
						base_h = @matrix_pts[1][0][2]
					end
					params['M_Hauteur'] = (params['M_Hauteur']/(top_h-base_h))*params['M_Hauteur']
					return create_convexdome(params,1,sens)
				end
				if(step==1)
					params['L_DOWN'] = @ground_pts[0][2]
					params['L_DOWN']-=params['L_SQUARES']
					return create_convexdome(params,2,sens)
				end
				if(step==2)
					#<CREATION>
					@dome_top_area = 0.0
					@squares_area = 0.0
					@total_top_area = 0.0
					if(params['T_Modelisation']=='Faces')
						@faces.each{|f|					
							face = @entities.add_face f
							face.back_material = params['RVB_BACK_FACES']
							face.material = params['RVB_FACES']
							
							if(params['L_EPAISSEUR']!=0)
								face.pushpull params['L_EPAISSEUR'], true
							end
							
							# mesh = face.mesh
							# point1 = Geom::Point3d.new 0,1,2
							# point2 = Geom::Point3d.new 1,0,2
							# point3 = Geom::Point3d.new 2,0,1
							# mesh.add_polygon point1, point2, point3
							# @group.add_faces_from_mesh mesh
							
							# @entities.add_cpoint f[0]
							# @entities.add_cpoint f[1]
							# @entities.add_cpoint f[2]
							
							area = face.area
							@dome_top_area+=area
							# area = face.area.inch*@u_inch*1000
							# @areas.push area.inch
						}
					else
						0.upto(params['N_Niveaux']-1){ |k|
							g_t = @tirants[k].to_f	
							g_a = @arretes[k].to_f
							area = aire_triangle_isocele gt, ga
							if(k!=0)
								g_t = @tirants[k].to_f
								g_a = @arretes[k-1].to_f
								area += aire_triangle_isocele gt, ga
							end
							@dome_top_area+=params['N_Cotes'].to_f*area.inch
						}
					end
					@dome_top_area = @dome_top_area*@u_inch*1000
					# if(@areas.length>0)
						# @areas = real_uniq( @areas )
						# @areas = @areas.reverse
					# end
					#</CREATION>
					return params
				end
			end
			
			def create_squares(params)
				0.upto(params['N_Cotes']-1){|i|
					f = []
					f.push @ground_pts[i]
					f.push @ground_pts[i-1]
					f.push [ @ground_pts[i-1][0], @ground_pts[i-1][1], @ground_pts[i-1][2]-params['L_SQUARES']]
					f.push [ @ground_pts[i][0], @ground_pts[i][1], @ground_pts[i][2]-params['L_SQUARES']]
					face = @entities.add_face f
					face.back_material = params['RVB_BACK_SOL']
					face.material = params['RVB_SOL']
					area = face.area
					@squares_area+=area
				}
				@squares_area = @squares_area*@u_inch*1000
				@total_top_area = @squares_area+@dome_top_area
			end
			
			def create_ground(params)
				if(params['T_Modelisation']=='Faces')
					if(params['L_SQUARES']==0)
						face = @entities.add_face @ground_pts
						face.back_material = params['RVB_BACK_SOL']
						face.material = params['RVB_SOL']
					else
						# face = @entities.add_face @ground_pts
						# face.back_material = params['RVB_BACK_SOL']
						# face.material = params['RVB_SOL']
					end
				end
			end
			
			def create_rapport(params)
			
				sixbranch_connection = (@connecteurs_nb-params['M_Cotes'])-1
				tubes_length = params["L_RayonConnecteurs"]*( (params['N_Cotes']*4)+(sixbranch_connection*6)+(params['N_Cotes']*5)+params['N_Cotes'] )
				tubes_length = tubes_length.inch
				rayonConnecteurs = params["L_RayonConnecteurs"].inch
				tirants_lenth = 0.0
				arretes_lenth = 0.0
				@tirants.each_index{ |k|
					tirants_lenth += params['N_Cotes']*@tirants[-(k+1)]
				}
				@arretes.each_index{ |k|
					if k==params['N_Niveaux']-1
						xna = params['N_Cotes']
					else
						xna = params['M_Cotes']
					end
					arretes_lenth += xna*@arretes[-(k+1)]
				}
				segments_lenth = arretes_lenth+tirants_lenth

				tirants_lenth = tirants_lenth.inch
				arretes_lenth = arretes_lenth.inch
				segments_lenth = segments_lenth.inch		
				
				msg = ""
				msg += " Sides: #{params["N_Cotes"]} \n"
				msg += " Levels: #{params["N_Niveaux"]} \n"
				msg += " Height: #{params["L_Hauteur"]} \n"
				msg += " Diameter: #{params["L_Diametre"]} \n"
				msg += " Ground area: #{@ground_area}² \n"
				msg += "\n Number of connectors: #{@connecteurs_nb} \n"
				msg += " #{params['N_Cotes']} x connectors 4"
				if(params['L_SQUARES']!=0)
					msg += " ou 5"
				end
				msg += " branches \n"
				msg += " #{sixbranch_connection} x connectors 6 branches \n"
				msg += " #{params['N_Cotes']} x connectors 5 branches \n"
				msg += " 1 x connector #{params['N_Cotes']} branches \n"
				msg += "\n Radius of connectors: #{rayonConnecteurs} \n"
				msg += "  -> Required Tube Length: #{tubes_length} \n"
				msg += "\n Total Number of Segments: #{@segments_nb} \n"
				msg += " Total Length of Segments: #{segments_lenth} \n"
				msg += " Number of horizontal segments: #{@tirants_nb} \n"
				msg += " Total length of horizontal segments: #{tirants_lenth} \n"
				msg_diametres = ""
				msg_hauteurs = ""
				msg_hauteursB = ""
				if(params['T_Rapport']=='Full')
					@tirants.each_index{ |k|
						msg += "    Level #{k+1}: #{params['N_Cotes']} Tirants de #{@tirants[-(k+1)]} \n"
						diam_niv = rayon_polygone_regulier params['N_Cotes'].to_f,@tirants[-(k+1)]
						diam_niv = diam_niv.to_l*2.0
						msg_diametres += "    Diameter at Level #{k+1}: #{diam_niv.inch} \n"
						msg_hauteurs += "    Height from ground at Level #{k+1}: #{@hauteurs[k].inch} \n"
						if(params['L_SQUARES']!=0)
							msg_hauteursB += "    Dome Height at Level #{k+1}: #{(@hauteurs[k]-params['L_SQUARES']).inch} \n"
						end
					}
				end
				
				msg += " \n"
				msg += msg_diametres+" \n"
				msg += msg_hauteurs+" \n"
				if(params['L_SQUARES']!=0)
					msg += msg_hauteursB+" \n"
				end
				
				msg += " Number of vertical segments: #{@arretes_nb} \n"
				msg += " Total length of vertical segments: #{arretes_lenth} \n"
				if(params['T_Rapport']=='Full')
					@arretes.each_index{ |k|
						if k==params['N_Niveaux']-1
							xna = params['N_Cotes']
						else
							xna = params['M_Cotes']
						end
						msg += "    Level #{k+1}: #{xna} vertical segments of #{@arretes[-(k+1)]} \n"
					}
				end
				msg += "\n Number of Triangles: #{@arretes_nb} \n"
				msg += " Total Area of triangles: #{@dome_top_area.inch}² \n"
				if(params['L_SQUARES']!=0)
					msg += " Total Area of Squares: #{@squares_area.inch}² \n"
					msg += " Total Area of Triangles+Squares: #{@total_top_area.inch}² \n"
				end
				if(params['T_Rapport']=='Full')
					level = 1
					@triangles.each_index{ |k|
						g_t = @triangles[k][0]
						g_a = @triangles[k][1]
						msg += "    Level #{level}     -> #{params['N_Cotes']} Triangles \n"
						msg += "        #{params['N_Cotes']} Vertical Segment     -> #{g_a.inch} \n"
						msg += "        #{params['N_Cotes']} Horizontal Segment   -> #{g_t.inch} \n"
						level+=0.5
					}
				end
				msg += "\n Number of Tiles: #{params['N_Cotes']*params['N_Niveaux']} (#{params['N_Cotes']*(params['N_Niveaux']-1)} lozenges + #{params['N_Cotes']} triangles) \n"
				msg += " With tiles overlapping of #{params['L_Tuilage'].inch} \n"
				velcro_l = 0.0
				level = 1
				i = 0
				perimar = params['L_Diametre_Arretes']*Math::PI
				velcl = perimar*1.5*3
				@dome_tiles_area = 0.0
				@tiles_triangles.each_index{ |k|
					if(k%2==0)
						g_t = @tiles_triangles[k][0]
						g_a2 = @triangles[k][1]
						area = aire_triangle_isocele(g_t,g_a2)
						velcro_l += (g_a2*2 + velcl)*params['N_Cotes']
						if(k==0)
							if(params['T_Rapport']=='Full')						
								msg += "    Level #{i+1}     -> #{params['N_Cotes']} Triangles \n"
								msg += "      Vertical Segment     -> #{g_a2.inch} \n"
								msg += "      Horizontal Segment   -> #{g_t.inch} \n"
							end
						else
							g_a1 = @tiles_triangles[k-1][1]
							if(params['T_Rapport']=='Full')						
								msg += "     Niveau #{i+1}     -> #{params['N_Cotes']} Cerf-volants \n"
								msg += "        Vertical Segment bottom  -> #{g_a1.inch} \n"
								msg += "        Horizontal Segment       -> #{g_t.inch} \n"
								msg += "        Vertical Segment top     -> #{g_a2.inch} \n"
							end
							velcro_l += (g_a1*2 + velcl)*params['N_Cotes']
							area += aire_triangle_isocele(g_t,g_a1)
						end
						@dome_tiles_area+=params['N_Cotes'].to_f*area.inch
						level+=1
						i+=1
					end
				}
				@dome_tiles_area = @dome_tiles_area*@u_inch*1000
				msg += "   -> Total Area of Tiles: #{@dome_tiles_area.inch}² \n"
				msg += "\n With vertical segment diameter of #{params['L_Diametre_Arretes'].inch}"
				msg += "\n and 1 velcro parallel + 3 perpendicular / vertical segment "
				msg += "\n     -> Total of required velcro: #{velcro_l.inch} \n"
				
				msg += "\n© Lozenge Dome Creator \OpenSource software developed by Jo - jo@redcat.ninja \nhttps://github.com/takion/dome-lozenge"
				
				@mo.add_note msg, 0, 0.03
			end #create_convexdome
			def create_tiles params #create_tiles
				@tiles_triangles.each_index{ |k|
					if(k%2==0)
						g_t = @tiles_triangles[k][0]
						if(k==0)
							g_a2 = @triangles[k][1]
							@tiles_isosceles.push([g_a2,g_t])
						else
							g_a1 = @tiles_triangles[k-1][1]
							g_a2 = @triangles[k][1]
							@tiles_isosceles.push([g_a1,g_t,g_a2])
						end
					end
				}
			
				espace_x = params['L_Tuilage']*2+500.mm
				espace_y = 0
				origine = [0,0,0]
				a = @tiles_isosceles[0][0]
				t = @tiles_isosceles[0][1]
				origine[1]+=t
				hiso = Math.sqrt( a*a - (t/2)*(t/2) )
				nx = [origine[0]+t,origine[1],origine[2]]
				ny = [origine[0]+t/2,origine[1]+hiso,origine[2]]
				rot = Geom::Transformation.rotation [ny[0],nx[1],nx[2]], Z_AXIS, 90.degrees
				ny = ny.transform(rot)
				nx = nx.transform(rot)
				loc_origine = origine.transform(rot)
				
				face = @entities.add_face loc_origine, nx, ny
				face.back_material = params['RVB_BACK_FACES']
				face.material = params['RVB_FACES']
				1.upto(params['N_Cotes']){ |n|
					if(n%2==0)
						face = @entities.add_face nx, ny, [ny[0],ny[1]+t]
						face.back_material = params['RVB_BACK_FACES']
						face.material = params['RVB_FACES']
					else
						if(n!=1)
							hh = t+espace_y
							loc_origine[1]+=hh
							ny = [ny[0],ny[1]+hh,ny[2]]
							nx = [nx[0],nx[1]+hh,nx[2]]
							face = @entities.add_face loc_origine, ny, nx
							face.back_material = params['RVB_BACK_FACES']
							face.material = params['RVB_FACES']
						end
					end
				}
				origine[1]-=t
				origine[0]+=hiso+espace_x
				1.upto(@tiles_isosceles.length-1){ |k|
					a = @tiles_isosceles[k][0]
					t = @tiles_isosceles[k][1]
					a2 = @tiles_isosceles[k][2]
					hiso = Math.sqrt( a*a - (t/2)*(t/2) )
					nx = [origine[0]+t,origine[1],origine[2]]
					ny = [origine[0]+t/2,origine[1]+hiso,origine[2]]
					hiso2 = Math.sqrt( a2*a2 - (t/2)*(t/2) )
					ny2 = [origine[0]+t/2,-(origine[1]+hiso2),origine[2]]
					
					rot = Geom::Transformation.rotation [ny[0],nx[1],nx[2]], Z_AXIS, 45.degrees
					ny = ny.transform(rot)
					nx = nx.transform(rot)
					ny2 = ny2.transform(rot)
					loc_origine = origine.transform(rot)
					
					0.upto(params['N_Cotes']-1){ |n|
						hh = a+espace_y
						loc_origine[1]+=hh
						ny = [ny[0],ny[1]+hh,ny[2]]
						nx = [nx[0],nx[1]+hh,nx[2]]
						ny2 = [ny2[0],ny2[1]+hh,ny2[2]]
						face = @entities.add_face loc_origine, ny, nx, ny2
						face.back_material = params['RVB_BACK_FACES']
						face.material = params['RVB_FACES']
					}
					origine[0]+=a+espace_x
				}
			end #create_tiles
			def show_matrix #show the array of points for debug and understanding
				msg = ''
				@matrix_pts.each_index{ |j|
					@matrix_pts[j].each_index{ |i|
						msg += " ["+j.to_s+"]["+i.to_s+"]: "+@matrix_pts[j][i].to_s+" \n"
					}
				}
				UI.messagebox(msg, MB_MULTILINE, "Lozenge Dome Matrix")
			end

		end

		UI.menu("Plugins").add_item("Lozenge Dome") { DomeLozenge.generation }
		file_loaded(File.basename(__FILE__))
		
	end
end
