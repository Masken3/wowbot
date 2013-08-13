#!/usr/bin/ruby

CONFIG_CCOMPILE_DEFAULT = 'debug'

require File.expand_path 'rules/cExe.rb'

class OpcodesTask < MultiFileTask
	def initialize
		@prerequisites = [FileTask.new('src/Opcodes.rb')]
		super('build/Opcodes.c', ['build/Opcodes.h'])
	end
	def fileExecute
		sh 'ruby src/Opcodes.rb'
	end
end

work = ExeWork.new do
	@SOURCES = ['src', 'src/worldMsgHandlers', 'server-code/Auth']
	o = OpcodesTask.new
	@SOURCE_TASKS = [o]
	@REQUIREMENTS = [o]
	@SPECIFIC_CFLAGS = {
		'worldPacketParsersLua.c' => ' -Wno-vla',
	}
	@EXTRA_INCLUDES = ['build', 'src', 'server-code', 'server-code/Auth']
	@LIBRARIES = ['crypto', 'z']
	if(HOST == :win32)
		@LIBRARIES += ['lua', 'wsock32', 'gdi32']
	elsif(HOST == :linux)
		@EXTRA_CFLAGS = ' '+open('|pkg-config --cflags lua5.2').read.strip
		@EXTRA_LINKFLAGS = ' '+open('|pkg-config --libs lua5.2').read.strip
		@LIBRARIES += ['rt']
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
