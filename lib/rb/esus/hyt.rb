#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# $KCODE = 'u'
# require 'jcode'

require 'optparse'

#require 'hylib'
require File.join(File.dirname($0), 'hylib')

def nl_strip(str)
   str.tr_s("\n", "¶")
end

def perform_listing(hylites, options)
   hylites.each_name do |attrib|
      level = attrib.level - 2
      indent = '  ' * level
      puts "#{indent}#{attrib.name}-"

      attrib.hyliteRefs.each do |hy|  # should be only one
         if options[:attributes]
            attr_str = (hy.attributes - [attrib]).map{|a| a.to_s_fancy}.join(' ')
            puts "#{indent}  :#{attr_str}" if attr_str.length > 0
         end
         if options[:text]
            hy.texts.each {|t| puts "#{indent}  “#{nl_strip(t.strip)}"}
         end
         if options[:locate]
            hy.locations.each {|loc| puts "#{indent}  @#{loc.to_s}"}
         end
      end
   end
   
   hylites.each_anon do |hylite|
      puts hylite.name_str

      if options[:attributes]
         attr_str = hylite.attributes.map{|a| a.to_s_fancy}.join(' ')
         puts "  :#{attr_str}" if attr_str.length > 0
      end
      if options[:text]
         hylite.texts.each {|t| puts "  “#{nl_strip(t.strip)}"}
      end
      if options[:locate]
         hylite.locations.each {|loc| puts "  @#{loc.to_s}"}
      end
   end
end

def perform_dir(hylites, options)
   hylites.each_attr do |attrib|
      level = attrib.level - 1
      indent = '  ' * level
      count = attrib.hyliteRefs.size
      case count
      when 0
         puts "#{indent}#{attrib.name}"
      when 1
         puts "#{indent}#{attrib.name} ·"
      else
         puts "#{indent}#{attrib.name} (#{count})"
      end
   end
end

def use_set(wset, options, optdata)
   def scan_working_set(wset)
      hylites = HyliteSet.new
      wset.each_file do |f|
         #puts "scanning #{f}…"
         scanner = Scanner.new(f)
         scanner.find_all_hylites(hylites)
      end
      hylites
   end

   if options[:covert]
      wset.see_hidden_files = true
   end

   if options[:debug_lws]
      puts "Working set is:"
      wset.each_file do |f|
         puts "  #{f}"
      end
   elsif options[:debug_hycount]
      hylites = scan_working_set(wset)
      puts "Found #{hylites.hylites.size} hylites"
   elsif options[:dir]
      hylites = scan_working_set(wset)
      perform_dir(hylites, options)
   else
      # if no other commands, do a listing
      hylites = scan_working_set(wset)

      if options[:fname]
         hylites = hylites.filter_name(optdata[:fname])
      end
      if options[:fgroup]
         hylites = hylites.filter_group(optdata[:fgroup])
      end
      if options[:fattr]
         hylites = hylites.filter_attr(optdata[:fattr])
      end
      perform_listing(hylites, options)
   end
end


# perform option parsing
options = {}
optdata = {}
optparse = OptionParser.new do |opts|
   opts.banner = "Usage: hyt.rb command [options] [file1 file2 ...]"

   options[:dir] = false
   opts.on('-d', '--dir', 'List a directory of all attributes') do
      options[:dir] = true
   end

   #########################################################
   # options controlling what files to examine

   options[:setfile] = false
   opts.on('-s', '--set', 'Use the specified working set file') do
      options[:setfile] = true
      optdata[:setfile] = ARGV.shift
   end

   options[:covert] = false
   opts.on('-c', '--covert', 'Also examine covert (hidden) files') do
      options[:covert] = true
   end

   #########################################################
   # options controlling what to look for (filtering)
   options[:fname] = false
   opts.on('-n', '--name', 'Search for the given name') do
      options[:fname] = true
      optdata[:fname] = ARGV.shift
   end

   options[:fgroup] = false
   opts.on('-g', '--group', 'Search for the name group') do
      options[:fgroup] = true
      optdata[:fgroup] ||= []
      optdata[:fgroup] << ARGV.shift
   end

   options[:fattr] = false
   opts.on('-A', '--fattr', 'Filter on the given attribute') do
      options[:fattr] = true
      optdata[:fattr] ||= []
      optdata[:fattr] << ARGV.shift
   end

   #########################################################
   # options controlling what's shown

   options[:attributes] = false
   opts.on('-a', '--attrib', 'List attributes') do
      options[:attributes] = true
   end

   options[:locate] = false
   opts.on('-l', '--location', 'List locations') do
      options[:locate] = true
   end

   options[:text] = false
   opts.on('-t', '--text', 'List text comment(s)') do
      options[:text] = true
   end
   
   #########################################################
   # options controlling debugging info

   options[:debug_lws] = false
   opts.on('--d_lws', 'Debug: list working set') do
      options[:debug_lws] = true
   end
   options[:debug_hycount] = false
   opts.on('--d_hyc', 'Debug: count hylites') do
      options[:debug_hycount] = true
   end

   opts.on('-h', '--help', 'Display this screen') do
      puts opts
      exit
   end

   opts.on('-v', '--version', 'Display the version') do
      puts VersionStr
      exit
   end
end
optparse.parse!

# perform command dispatch
begin
   if ARGV.size == 0
      if File::readable?("./.hylite")
         wset = WorkingSet.new("./.hylite")
         use_set(wset, options, optdata)
      end
   elsif options[:setfile]
      #setfile = ARGV.shift
      setfile = optdata[:setfile]
      wset = WorkingSet.new(setfile)
      use_set(wset, options, optdata)
   else
      # pull all filenames from the command line and call them the working set
      wset = ManualSet.new(*ARGV)
      use_set(wset, options, optdata)
   end
rescue Exception => e
   puts 'hyt top error…'
   puts e.message
   puts e.backtrace
end

