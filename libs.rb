require './config.rb'
require File.expand_path "#{CONFIG_WOWFOOT_DIR}/rules/cDll.rb"
require File.expand_path "#{CONFIG_WOWFOOT_DIR}/rules/cLib.rb"
require "#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers/dbc/dbc.rb"

CONFIG_LIBSRC = "#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src/libs"
require "#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/config.rb"
require "#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/libs.rb"

if(HOST == :linux)
	LUA_CFLAGS = ' '+open('|pkg-config --cflags luajit').read.strip
	LUA_LINKFLAGS = ' '+open('|pkg-config --libs luajit').read.strip
elsif(HOST == :win32)
	LUA_CFLAGS = " -I#{CONFIG_LUAJIT_INCLUDE_DIR}"
end

DBC = DllWork.new do
	@SOURCES = [
		CONFIG_LIBSRC,
	]
	@SOURCE_FILES = ["#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src/dbcList.cpp"]
	@EXTRA_INCLUDES =[
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src",
		"#{CONFIG_LIBSRC}/libmpq",
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
			@SOURCE_TASKS << DbcCppTask.new(name, {:criticalSection=>false, :lua=>true, :logging=>false})
			@EXTRA_OBJECTS = [DBC]
			@EXTRA_CPPFLAGS = LUA_CFLAGS
			if(HOST == :win32)
				@LIBRARIES = ['lua51']
			elsif(HOST == :linux)
				@EXTRA_LINKFLAGS = LUA_LINKFLAGS
			end
			@NAME = name
			instance_eval(&block) if(block)
		end
	end
end

DBCs = [
	'dbcSpell',
	'dbcSpellDuration',
	'dbcSpellRange',
	'dbcSpellCastTimes',
	'dbcSpellItemEnchantment',
	'dbcLock',
	'dbcSkillLineAbility',
	'dbcSkillLine',
	'dbcTalent',
	'dbcTalentTab',
	'dbcSpellIcon',
	'dbcItemDisplayInfo',
	'dbcFactionTemplate',
]

DBC_WORKS = DBCs.collect do |d| DbcWork.new(d) end

ICON = DllWork.new do
	@SOURCES = ["#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers/icon"]
	@EXTRA_INCLUDES = [
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src/libs",
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-ex/src/libs/libmpq",
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers/dbc",
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp",
	]
	@EXTRA_CPPFLAGS = " -DWOWBOT=1 -DICONDIR_BASE=\"\\\"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/\\\"\""
	@prerequisites = [DirTask.new("#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/build/icon")]
	@EXTRA_OBJECTS = [DBC, (LIBMPQ), (BLP), (SQUISH), (PALBMP), (CRBLIB)]
	@LIBRARIES = ['png', 'jpeg']
	@NAME = 'icon'
end
