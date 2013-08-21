
# Generates C code that sets Lua constants matching enum values in the source header file.
# Generates one .c and one .h file.
class GenLuaFromHeaderTask < MultiFileTask
	def initialize(name, srcName)
		@name = name
		@src = srcName
		@prerequisites = [FileTask.new(@src), FileTask.new(__FILE__)]
		@cName = "build/#{name}Lua.c"
		@hName = "build/#{name}Lua.h"
		super(@cName, [@hName])
	end
	def fileExecute
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
				file.puts "\tlua_setglobal(L, \"#{name}\");"
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
				elsif(inEnum)
					if(line.strip == '};')
						inEnum = false
					else
						arr = line.scan(/\s*(.+)\s*=([^,]+),/)
						if(arr[0])
							name, value = arr[0].collect do |t| t.strip; end
							enums[eName][name] = value
						end
					end
				elsif(line.strip == '{')
					inEnum = true
				end
			end
		end
		return enums
	end
end

