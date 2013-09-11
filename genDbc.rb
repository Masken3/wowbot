require 'stringio'

class DbcContainer
	attr_reader(:singular, :plural, :dbcName)
	def initialize(name)
		src = "#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers/#{name}/#{name}.rb"
		instance_eval(open(src).read, src)
	end
end

class GenDbcTask < MemoryGeneratedFileTask
	def initialize(dbcs)
		c = {}
		dbcs.each do |dbc|
			c[dbc] = DbcContainer.new(dbc)
		end
		io = StringIO.new
		io.puts 'extern "C" {'
		io.puts '#include <lauxlib.h>'
		io.puts '}'
		io.puts '#include "cDbc.h"'
		dbcs.each do |dbc|
			io.puts "#include \"../build/#{dbc}/#{dbc}.h\""
		end
		io.puts
		io.puts 'void loadDBC(void) {'
		dbcs.each do |dbc|
			io.puts "\tg#{c[dbc].plural}.load();"
		end
		io.puts '}'
		dbcs.each do |dbc|
			d = c[dbc]
			io.puts
			io.puts "static int l_#{d.singular.downcase}(lua_State* L) {"
			io.puts "\tint narg = lua_gettop(L);"
			io.puts "\tif(narg != 1) {"
			io.puts "\t\tlua_pushstring(L, \"l_#{d.singular.downcase} error: args!\");"
			io.puts "\t\tlua_error(L);"
			io.puts "\t}"
			io.puts "\tint id = luaL_checkint(L, 1);"
			io.puts "\tconst #{d.singular}* s = g#{d.plural}.find(id);"
			io.puts "\tif(s)"
			io.puts "\t\tluaPush#{d.singular}(L, *s);"
			io.puts "\telse"
			io.puts "\t\tlua_pushnil(L);"
			io.puts "\treturn 1;"
			io.puts '}'
		end
		io.puts
		io.puts 'void registerLuaDBC(lua_State* L) {'
		dbcs.each do |dbc|
			io.puts "\tlua_register(L, \"c#{c[dbc].singular}\", l_#{c[dbc].singular.downcase});"
		end
		io.puts '}'
		@buf = io.string
		super('build/cDbc.cpp')
	end
end
