
# Generates C code that sets Lua constants matching enum values in the source header file.
# Generates one .c and one .h file.
# options:
# :includedEnums, array of strings. if set, all enums not in this set will be discarded.
class GenLuaFromHeaderTask < MultiFileTask
	include FlagsChanged
	def initialize(name, srcName, options = {})
		@name = name
		@src = srcName
		@prerequisites = [FileTask.new(@src), FileTask.new(__FILE__)]
		@cName = "build/#{name}Lua.c"
		@hName = "build/#{name}Lua.h"
		@options = options
		# todo: cause rebuild if options change.
		super(@cName, [@hName])
	end
	def cFlags
		return @options.inspect
	end
	def fileExecute
		execFlags
		enums = parse(@src)
		open(@cName, 'w') do |file|
			writeC(@src, file, enums)
		end
		open(@hName, 'w') do |file|
			writeH(file, enums)
		end
	end
	def writeC(src, file, enums)
		file.puts "#include <lua.h>"
		file.puts "#include \"#{@name}Lua.h\""
		file.puts "#include \"../#{src}\""
		file.puts
		file.puts "void #{@name}Lua(lua_State* L) {"
		enums.each do |eName, values|
			values.each do |name, value|
				file.puts "\tlua_pushnumber(L, #{name});"
				file.puts "\tlua_setglobal(L, \"#{value}\");"
			end
		end
		file.puts "}"
	end
	def writeH(file, enums)
		file.puts "#ifndef #{@name}_H"
		file.puts "#define #{@name}_H"
		file.puts
		file.puts "void #{@name}Lua(lua_State*);"
		file.puts
		file.puts "#endif\t//#{@name}_H"
	end
	def parse(src)
		enums = {}
		open(src, 'r') do |file|
			eName = nil
			inEnum = false
			file.each do |line|
				if(line.start_with?('enum'))
					eName = line.split[1]
					raise if(enums[eName])
					enums[eName] = {}
				elsif(line.strip.start_with?('//'))
					# comment
				elsif(inEnum)
					if(line.strip == '};')
						inEnum = false
					else
						arr = line.scan(/\s*(.+)\s*=([^,]+),/)
						if(arr[0])
							name, value = arr[0].collect do |t| t.strip; end
							if(@options[:cutPrefix])
								value = name[name.index('_')+1 .. -1]
							else
								value = name
							end
							enums[eName][name] = value
						end
					end
				elsif(line.strip == '{')
					ie = @options[:includedEnums]
					if(ie && !ie.include?(eName))
						next
					else
						inEnum = true
					end
				end
			end
		end
		if(@options[:includedEnums])
			@options[:includedEnums].each do |ie|
				#puts "test #{ie}"
				raise ie if(!enums[ie])
				raise ie if(enums[ie].empty?)
			end
		end
		return enums
	end
end

