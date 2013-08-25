#!/usr/bin/ruby

CONFIG_CCOMPILE_DEFAULT = 'debug'

require File.expand_path 'rules/cExe.rb'
require './genLuaFromHeader.rb'
require './libs.rb'

class GenTask < MultiFileTask
	def initialize(name)
		@src = "src/#{name}.rb"
		@prerequisites = [FileTask.new(@src)]
		super("build/#{name}.c", ["build/#{name}.h"])
	end
	def fileExecute
		sh "ruby #{@src}"
	end
end

work = ExeWork.new do
	@SOURCES = ['src', 'src/worldMsgHandlers', 'server-code/Auth']
	@SOURCE_FILES = [
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers/spell/spellStrings.cpp",
	]
	@SOURCE_TASKS = @REQUIREMENTS = [
		GenTask.new('Opcodes'),
		GenTask.new('movementFlags'),
		GenLuaFromHeaderTask.new('UpdateFields', 'server-code/UpdateFields.h'),
		GenLuaFromHeaderTask.new('updateBlockFlags', 'src/updateBlockFlags.h'),
	]
	@SPECIFIC_CFLAGS = {
		'worldPacketParsersLua.c' => ' -Wno-vla',
		'cDbc.cpp' => " -I#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers"+
			" -I#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp",
		'exception.cpp' => " -I#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp",
	}
	@EXTRA_INCLUDES = ['build', 'src', 'server-code', 'server-code/Auth',
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers/spell",
	]
	@EXTRA_OBJECTS = [DBC_SPELL]
	@LIBRARIES = ['crypto', 'z']
	if(HOST == :win32)
		@SOURCES << "#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/util/win32"
		@SOURCES << "#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/util/win32/sym_engine"
		@LIBRARIES += ['lua', 'wsock32', 'gdi32', 'imagehlp']
	elsif(HOST == :linux)
		@SOURCES << "#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/util/unix"
		@EXTRA_CFLAGS = ' '+open('|pkg-config --cflags lua5.2').read.strip
		@EXTRA_LINKFLAGS = ' '+open('|pkg-config --libs lua5.2').read.strip
		@LIBRARIES += ['rt']
		#@LIBRARIES = ['dl']
	else
		raise "Unsupported platform: #{HOST}"
	end
	@NAME = 'wowbot'
end

target :run do
	sh "#{work}"
end

target :gdb do
	sh "gdb --args #{work}"
end

target :mc do
	sh "valgrind --leak-check=full #{work}"
end

Works.run
