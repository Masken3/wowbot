#!/usr/bin/ruby

require File.expand_path 'rules/cExe.rb'

work = ExeWork.new do
	@SOURCES = ['src', 'server-code/Auth']
	@EXTRA_INCLUDES = ['src', 'server-code', 'server-code/Auth']
	@LIBRARIES = ['wsock32', 'crypto', 'gdi32']
	@NAME = 'import'
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
