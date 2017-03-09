#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

$KCODE = 'u'
require 'jcode'

require 'optparse'

require 'hylib'

# hylite: >: option parsing for -r, recursive, for when fname from ARGV  is a directory

def dump_all
   hylites = HyliteSet.new
   ARGV.each do |fname|
      if not File::readable?(fname)
         puts "ERROR: can't read file #{fname}"
         next
      end
      next if File::directory?(fname)

      scanner = Scanner.new(fname)
      scanner.findAllHylites(hylites)
   end

   hylites.each_name do |attrib|
      level = attrib.level - 2
      indent = '  ' * level
      puts "#{indent}#{attrib.name}-"

      # hylites of attrib.each do
      attrib.hyliteRefs.each do |hy|
         #    non-name labels.non-root strings.join
         attr_str = (hy.attributes - [attrib]).map{|a| a.to_s_fancy}.join(' ')
         puts "#{indent}  :#{attr_str}" if attr_str.length > 0

         hy.locations.each {|loc| puts "#{indent}  @#{loc.to_s}"}
         hy.texts.each {|t| puts "#{indent}  “#{t}"}
      end
   end
end

def list(options)
   hylites = HyliteSet.new

   def list_recurse(fname)
      # switch on file state: check file
      # if recurse option & recursable, recurse
      # not readable, recursable, simple
      if
      else
         scanner = Scanner.new(fname)
         scanner.findAllHylites(hylites)
      end
   end
   ARGV.each do |fname|
      list_recurse(fname)
   end

   hylites.each_name do |attrib|
      level = attrib.level - 2
      indent = '  ' * level
      puts "#{indent}#{attrib.name}-"

      attrib.hyliteRefs.each do |hy|  # should be only one
         if options[:attributes]
            attr_str = #etcetera
         end
         if options[:text]
            hy.texts.each {|t| puts "#{indent}  “#{t}"}
         end
         if options[:locate]
            hy.locations.each {|loc| puts "#{indent}  @#{loc.to_s}"}
         end
      end
   end
end

# perform option parsing
options = {}
optparse = OptionParser.new do |opts|
   opts.banner = "Usage: hyt.rb [options] command [file1 file2 ...]"

   options[:recurse] = false
   opts.on('-r', '--recurse', 'Recurse into subdirectories') do
      options[:recurse] = true
   end

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

   opts.on('-h', '--help', 'Display this screen') do
      puts opts
      exit
   end
end
optparse.parse!

# perform command dispatch
begin
   case ARGV.shift
   when "dump"
      dump_all
   when "list"
      list(options)
   else
      puts "not a recognized command"
   end
rescue Exception => e
   puts 'TOP LEVEL ERROR'
   puts e.message
   puts e.backtrace
end
