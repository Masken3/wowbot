require File.expand_path 'rules/cDll.rb'
require './config.rb'
require "#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers/dbc/dbc.rb"

commonFlags = ' -Wno-all -Wno-extra -Wno-c++-compat -Wno-missing-prototypes -Wno-missing-declarations -Wno-shadow'

if(HOST == :linux)
	LUA_CFLAGS = ' '+open('|pkg-config --cflags lua5.2').read.strip
	LUA_LINKFLAGS = ' '+open('|pkg-config --libs lua5.2').read.strip
end

LIBMPQ = DllWork.new do
	@SOURCES = [
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src/libs/libmpq/libmpq",
	]
	@EXTRA_INCLUDES = [
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src/libs/libmpq",
	]
	@EXTRA_CFLAGS = commonFlags
	#@EXTRA_LINKFLAGS = ' -symbolic'
	@LIBRARIES = ['bz2', 'z']
	@LIBRARIES << 'mingwex' if(HOST == :win32)
	@NAME = 'libmpq'
end

DBC = DllWork.new do
	@SOURCES = [
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src/libs",
	]
	@SOURCE_FILES = ["#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src/dbcList.cpp"]
	@EXTRA_INCLUDES =[
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src",
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src/libs/libmpq",
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp",
	]
	@SPECIFIC_CFLAGS = {
		'dbcList.cpp' => " -DCONFIG_WOW_VERSION=#{CONFIG_WOW_VERSION}",
	}
	@IGNORED_FILES = [
		'loadlib.cpp',
	]
	@EXTRA_OBJECTS = [LIBMPQ]
	@NAME = 'dbc'
end

class DbcWork < DllWork
	def initialize(name, &block)
		super(DefaultCCompilerModule) do
			@EXTRA_INCLUDES = [
				"#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src/libs",
				"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers/dbc",
				"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers",
				"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp",
				"build/#{name}",
			]
			@SOURCE_TASKS ||= []
			@SOURCE_TASKS << DbcCppTask.new(name, {:criticalSection=>false, :lua=>true})
			@EXTRA_OBJECTS = [DBC]
			if(HOST == :win32)
				@LIBRARIES = ['lua']
			elsif(HOST == :linux)
				@EXTRA_CPPFLAGS = LUA_CFLAGS
				@EXTRA_LINKFLAGS = LUA_LINKFLAGS
			end
			@NAME = name
			instance_eval(&block) if(block)
		end
	end
end

DBC_SPELL = DbcWork.new('dbcSpell')
