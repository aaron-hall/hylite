#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

# $KCODE = 'u'

#########1#########2#########3#########4#########5#########6#########7#########8#########9########10

# require 'jcode'
require 'yaml'
require 'set'


VersionStr = 'Hylites 107 ¹JZ7L'

# A hylite object. Each hylite has sets (Array really) of attributes, texts, and locations.
#
# Each attribute is a reference to a node in the attribute tree, only one of which will be the name.
# The hylite object caches requests for its name string, as common as that is.
#
# Each text is a string of the text part of one writing of this hylite.
#
# Each location is a file location of a writing of the hylite.

class Hylite
   attr_reader :attributes, :texts, :locations
   attr_writer :texts, :locations
   
   @@anon_id = 1

   def initialize()
      @attributes = Array.new
      @texts = Array.new
      @locations = Array.new
   end

   def anonymous?
      not @attributes.any? do |attr|
         runner = attr
         while runner.upRef
            if runner.name == '_Name' and runner.upRef.name == '_Root'
               break true
            else
               runner = runner.upRef
            end
         end
      end
   end

   def name_str
      if @name_str
         @name_str
      else
         @attributes.each do |attr|
            attr_a = attr.to_a
            if attr_a.size >= 2 and attr_a[0] == '_Root' and attr_a[1] == '_Name'
               @name_str = attr_a.drop(2).join('-')
            end
         end
         unless @name_str
            @name_str = "_Anon-%d" % [@@anon_id]
            @@anon_id += 1
         end
         @name_str
      end
   end

   def add_attribute(attrib)
      @attributes << attrib unless @attributes.include?(attrib)
   end

   def to_s
      result = String.new("hylite #{name_str}: ")
      attributes.each do |attribute|
         result << attribute.to_s << ' '
      end
      result << ':'
      texts.each do |text|
         result << text << '``'
      end
      return result
   end
end


# Represents one location of a Hylite (which may have several). Each location is a combination of a
# filename and line number.

class Location
   def initialize(file, line)
      @file = file
      @line = line
   end

   attr_reader :file, :line
   attr_writer :file, :line

   def to_s
      "#{@file}:#{@line}"
   end
end


# A single node in the attribute tree. These attribute nodes can represent true attributes or
# names, if in the right “directory”. Several of the methods are for walking the tree, as the
# root node can be the entry point for traversing the tree.
#
# An attribute node has a string for its own name, a reference to its single parent node,
# a map of its children indexed by their names (for convenience), and a list of all hylite
# objects that reference this attribute—whether as their name or as an attribute.
#
# All attributes begining with an underscore are reserved for internal use. In particular this
# implementation uses these reserved names:
#    _Root the root of the attrib tree
#    _Name the root of the name subtree, a child of _Root
#    _Anon sometimes represents the root name of anonymous hylites (not
#          stored in the tree)

class AttribNode
   attr_reader :name, :upRef, :downRefs, :hyliteRefs
   attr_writer :upRef, :downRefs, :hyliteRefs

   def initialize(name)
      @name = name
      @downRefs = Hash.new
      @hyliteRefs = Array.new
   end

   def seek(attribName)
      runner = self
      attribName.each_line('-') do |partName|
         runner = runner.downRefs[partName.chomp('-')]
         return runner if (runner == nil)
      end
      return runner
   end

   def seekMake(attrib_name)
      runner = self
      attrib_name.each_line('-') do |part_name|
         part_name.chomp!('-')
         old_runner = runner
         runner = runner.downRefs[part_name]
         if runner == nil                                   # then create an attribute node there
            runner = AttribNode.new(part_name)
            runner.upRef = old_runner
            old_runner.downRefs[part_name] = runner
         end
      end
      return runner
   end

   def level
      lev = 0
      runner = self
      while runner.upRef != nil
         lev += 1
         runner = runner.upRef
      end
      lev
   end

   def to_s
      if @upRef == nil
         "#{@name}"
      else
         "#{@upRef.to_s}-#{@name}"
      end
   end

   def to_s_fancy
      if @upRef == nil
         nil
      else
         upstr = @upRef.to_s_fancy
         if upstr
            "#{upstr}-#{@name}"
         else
            @name
         end
      end
   end

   # returns a representation of this attribute as an array of strings (its "path")
   def to_a
      if @upRef == nil
         [@name]
      else
         @upRef.to_a << @name
      end
   end
end

# Base class of all hylite sets. It exists to factor out a couple common functions.

class AbstractHyliteSet
   # Remove all hylites that don't match the given name
   def filter_name(name)
      HyliteSetView.new(self) do |hy|
         if name.kind_of? Regexp
            name =~ hy.name_str
         else
            name == hy.name_str
         end
      end
   end

   # Remove all hylites that don't match the OR of the given groups
   def filter_group(groups)
      groups = [groups] unless groups.kind_of? Enumerable

      # return an HSV with the given decider proc
      HyliteSetView.new(self) do |hy|

         # look for any group in the given Enumerable that passes the predicate5
         groups.any? do |group|
            # is group (as a string) a prefix of hy.name_str?
            hy.name_str.index(group) == 0
         end
      end
   end

   # the OR of the given attributes
   def filter_attr(attrs)
      # protection may not be necessary
      attrs = [attrs] unless attrs.kind_of? Enumerable

      found_any = false
      hsv = HyliteSetView.new(self)
      hsv.mode = :exclude

      attrs.each do |attr|
         node = @attribTree.seek(attr)
         if node and not node.hyliteRefs.empty?
            hsv.include.merge(node.hyliteRefs)
            found_any = true
         end
      end

      if found_any
         hsv
      else
         EmptyHSV.new(self)
      end
   end
end


# A set of hylites. Contains a list of the hylite objects, and a reference to the root of the attrib
# tree. Has convenience methods for iterating the hylites or attributes in various ways.  Is
# specifically designed to be wrapped by a filter (set view) to access only certain hylites or
# attributes. It inherits methods for creating such a wrapper from its superclass,
# AbstractHyliteSet.

class HyliteSet < AbstractHyliteSet
   attr_reader :hylites, :attribTree

   def initialize
      @hylites = Array.new
      @attribTree = AttribNode.new("_Root")
   end

   def each_name(&proc)
      name = @attribTree.seek('_Name')
      return if not name
      each_walker(name, proc)
   end

   def each_anon
      @hylites.each do |hy|
         yield hy if hy.anonymous?
      end
   end
   
   def each_attr(&proc)
      each_walker(@attribTree, proc)
   end

   # Internal implementation for walking the attrib tree given a starting point. This
   # factors the common implementation for each_name and each_attr.
   def each_walker(start, proc)
      visit = lambda do |node|
         proc.call(node) if node != start
         node.downRefs.keys.sort.each do |key|
            visit.call(node.downRefs[key])
         end
      end
      visit.call(start)
   end
end


# A filter or wrapper around a HyliteSet, that limits the hylites iterated over to certain
# kinds. (Iterating over all attributes is unchanged.) It has three modes: in mode :include it
# includes everything except a given set of hylites. In mode :exclude it excludes everything except
# a given set of hylites. In mode :decider it delegates that decision to the proc supplied to the
# constructor. (The decider proc is expected to take one hylite and return a boolean-ish.)
#
# As a subclass of AbstractHyliteSet, these can also wrap themselves in yet another filter
# to chain various rules.
#
# Members:
# @mode the mode of this set view
# @include the set (actual Set) of hylites to be included during mode :exclude
# @exclude the set (also a Set) of hylites to be excluded during mode :include
# @decider the decider Proc that decides whether a given hylite is visible

class HyliteSetView < AbstractHyliteSet
   attr_accessor :mode, :include, :exclude

   def initialize(set, &decider)
      @backing_set = set

      if decider
         @mode = :decider
         @decider = decider
      else
         @mode = :include  # include all except for listed exclusion set
         @include = Set.new
         @exclude = Set.new
      end
   end
   
   def each_name
      @backing_set.each_name do |name|
         hylite = name.hyliteRefs[0]  # should be zero or only one for name attribute
         next unless hylite
         if hylite_is_visible(hylite)
            yield name
         end
      end
   end

   def each_anon
      @backing_set.each_anon do |hylite|
         yield hylite if hylite_is_visible(hylite)
      end
   end

   def each_attr(&proc)
      @backing_set.each_attr(proc)
   end

   def hylite_is_visible(hy)
      case @mode
      when :decider
         # delegate to the provided proc whether this hylite is included
         @decider.call(hy)
      when :include
         # include by default, see @exclude set for exceptions
         not @exclude.include?(hy)
      when :exclude
         # exclude by default, see @include set for exceptions
         @include.include?(hy)
      else
         raise "HyliteSetView has unknown mode #{@mode}"
      end
   end
end


# A HyliteSetView wrapper/filter that fails all hylites. It keeps the same interface (and may be
# re-wrapped with other filters) but it doesn't matter, it fails to propagate the iterators.

class EmptyHSV < AbstractHyliteSet
   attr_accessor :mode, :include, :exclude

   def initialize(set)
      @backing_set = set
   end

   def each_name
      # do nothing
   end

   def each_anon
      # do nothing
   end
end


$extension_to_type_map = {}
TYPE_TO_EXTENSION_MAP = {
   :java => ['java'],
   :c    => ['c', 'h'],
   :cpp  => ['c++', 'cpp'],
   :perl => ['pl', 'perl'],
   :ruby => ['rb', 'ruby', 'rbw'],
   :text => ['txt', 'out'],
   :html => ['html', 'htm'],
   :xml  => ['xml', 'jtdl', 'jtdli', 'jul'],
   :yaml => ['yaml', 'yml']
}
TYPE_TO_EXTENSION_MAP.each do |type, xs|
   xs.each{|x| $extension_to_type_map[x] = type}
end

# A Scanner is responsible for examining a single file and adding any hylite writings found there to
# a HyliteSet. That gets very complicated.

class Scanner
   @@comment_delimiters = {
      :java => ['//', '/*', '*/'],
      :c    => ['//', '/*', '*/'],
      :cpp  => ['//', '/*', '*/'],
      :html => [nil, '<!--', '-->'],
      :perl => ['\x23', nil],               # hash character
      :ruby => ['\x23', nil],               # another hash character
      :xml  => [nil, '<!--', '-->'],
      :yaml => ['\x23', nil]
   }
   
   @@embedded_delimiters = {
      '(' => ')',
      '[' => ']',
      '{' => '}',
      '<' => '>',
      '«' => '»',
      '“' => '”',
      '‘' => '’',
      '⟨' => '⟩',
      '⌈' => '⌉',
      '⌊' => '⌋',
      '⧼' => '⧽',
      '‹' => '›',
      '【' => ' 】'
   }

   @@punt_mode = false


   # During the scanning process text that may contain hylites is moved from the file to a buffer of
   # CommentParts (so named because in every file type but :text this is only text inside a
   # comment). Each CommentPart is at most one line, with the line number, and a flag indicated
   # whether it's “terminated” (for example, the last line of a block comment would be terminated,
   # as would a single-line comment, but the first line of a multiline block comment would not.)

   class CommentPart
      attr_reader :line, :string, :terminated
      attr_writer :string

      def initialize(line, string, terminated)
         @line = line
         @string = string
         @terminated = terminated
      end

      def to_s
         "(#{@line}|#{@string}|#{@terminated ? '.' : ''})"
      end
   end

   # A hylite part is a string representing a writing of a hylite, along with its line number.  In
   # the scanning process these are created from CommentParts and are parsed to produce hylites.

   class HylitePart
      attr_reader :line, :string
      attr_writer :string

      def initialize(line, string)
         @line = line
         @string = string
      end

      def to_s
         "(#{@line}|#{@string})"
      end
   end

   # Initialize the Scanner itself. The HylitePart buffer and CommentPart buffer are empty, and the
   # current line number of the file is zero. The default language is :text.
   def initialize(file)
      @file = file
      
      @language = :text

      @hy_part_buf = []
      @comment_part_buf = []
      @line_no = 0
   end
   

   def find_all_hylites(result)
      #determine file type
      @language = determine_type()
      
      #puts "   detected language #{@language}"

      if @@punt_mode
         File.new(@file, 'r').each_with_index do |line, ix|
            hystr = line_hylite(line)
            if hystr
               hy = parse_hylite_string(hystr, result)
               hy.locations << Location.new(@file, ix)
            end
         end
      else
         #puts "scanning file #{@file}"
         File.open(@file, 'r') do |file|
            while hp = next_hylite_part(file)
#               puts "   got hp ⌈#{hp}⌉"
               hy = parse_hylite_string(hp.string, result)
#               puts "      parsed as ⌈#{hy}⌉"
               hy.locations << Location.new(@file, hp.line)
            end
         end
      end
   end
   
   def determine_type()
      # get extension to file
      if /.*\.(.+)/ =~ @file
         type = $extension_to_type_map[$~[1]]

         # for now, go with this or use text (may do fancy checking later)
         type || :text
      else
         :text
      end
   end

   def line_hylite(line)
      if /.*(hylite\s.*).*$/ =~ line
         $~[1]
      elsif /.*(hylite:+.*).*$/ =~ line  # anonymous hylites
         $~[1]
      else
         nil
      end
   end

   # hylite parts are the string representation and the line number they came from
   def next_hylite_part(file)
      while @hy_part_buf.empty?
         part = next_comment_part(file)
         return nil if not part  # eof catching

#         puts "...........comment part “#{part}”"

         # iterate processing the string of this part (to allow multiple hylites per part)
         while part and part.string and part.string.length > 0
            # find “hylite” in the part, loop if not present, skip over spurious naming
            hy_pos = part.string.index("hylite")

            break if not hy_pos
            unless [':', ' '].include?(part.string[hy_pos+6...hy_pos+7])
               # character immediately after is neither colon nor space
               part.string = part.string[hy_pos+7..-1]
               next
            end
#            puts "  found hylite in #{part.string} at #{part.string[hy_pos..-1]}"

            # check before it for grouping character
            grouper = if hy_pos > 0
                         # use regex recapture for unicode-friendliness
                         /(.)hylite/ =~ part.string
                         left_char = $~[1]
                         #left_char = part.string[hy_pos-1 ... hy_pos]
#                         puts "    left char is [#{left_char}]"
                         # grouper will be the matching right delimiter or nil
                         @@embedded_delimiters[left_char]
                      else
                         nil
                      end

#            puts "  grouper #{grouper}" if grouper
            unless grouper
               # no grouping, the bounds of this hylite are determined by the comment (or text mode)
               if part.terminated or @language == :text
                  # line mode, the whole rest of the line is one hylite part
                  @hy_part_buf << HylitePart.new(part.line, part.string[hy_pos..-1])
                  part = nil

               else
                  # block comment mode, the rest of the line is only the beginning
                  hypart = HylitePart.new(part.line, part.string[hy_pos..-1])

                  # loop consuming comment parts, appending to ongoing hylite, until terminated
                  # also breaks loop on eof
                  while part and not part.terminated
                     part = next_comment_part(file)
                     if part
                        hypart.string << (' ' + part.string)
                     end
                  end

                  # buffer the now-completed hylite part (even if eof)
                  @hy_part_buf << hypart
                  part = nil
               end

            else
               # grouping, look for matching grouper
               groupos = part.string.index(grouper)
               if groupos
                  # the grouped hylite part appears all on one line; consume it and
                  # loop back to continue processing the rest of this comment part
                  # edit: use the RE engine to properly handle unicode
                  # edit: or not. (1 of 2)
#                  re = Regexp.new(".*(hylite.*)\\#{grouper}(.*)$")
#                  re =~ part.string
#                  raise "what an odd error!" unless $~
#                  @hy_part_buf << HylitePart.new(part.line, $1)
#                  part.string = $2
                  @hy_part_buf << HylitePart.new(part.line, part.string[hy_pos...groupos])
                  part.string = part.string[(groupos+1) .. -1]
#                  puts "      made #{@hy_part_buf[-1]} and string is #{part.string}"
                  
               elsif part.terminated
#                  puts "    group terminated prematurely on #{part}"
                  # the hylite may be grouped but by mistake the comment ends first
                  # use this much and stop
                  @hy_part_buf << HylitePart.new(part.line, part.string[hy_pos..-1])
                  part = nil
#                  puts "      made #{@hy_part_buf[-1]}"

               else
                  # the grouped hylite begins on this line but keeps going, iterate after it
                  hypart = HylitePart.new(part.line, part.string[hy_pos..-1])
#                  puts "    group begins here, so far, #{hypart}"

                  while true
                     part = next_comment_part(file)
                     break unless part

#                     puts "      next part #{part}"

                     groupos = part.string.index(grouper)
                     if groupos
                        # found the end of the hylite, finish it, consume the comment part and
                        # loop way back to continue its processing for more hylites
                        # edit: another place where the RE engine fixes unicoding
                        # edit: or perhaps not, in 1.9; may have to change again for 2
                        #re = Regexp.new("(.*)\\#{grouper}(.*)$")
                        #re =~ part.string
                        #raise "another head-scratcher!" unless $~
                        #hypart.string << (' ' + $1)
                        #part.string = $2
                        hypart.string << (' ' + part.string[0...groupos])
                        part.string = part.string[(groupos+1)..-1]
                        break

                     elsif part.terminated
                        # also a grouped hylite that hits the comment end first
                        hypart.string << (' ' + part.string)
                        part = nil
                        break

                     else
                        # one line of an onging hylite
                        hypart.string << (' ' + part.string)
                        part = nil

                     end
                  end # while true

                  # buffer the now-completed hylite part (even if eof)
                  @hy_part_buf << hypart
               end

            end # unless grouper

            # if there's still a part, and it still has some string content, loop back and
            # continue parsing (accounts for lines where one hylite ends and another begins)
         end # while part and part.string…

         # after processing one or more parts, if the buffer's still empty, loop back
      end # while @hy_part_buf.empty?

      # at this point the buffer has something, or eof (shift returns nil)
      @hy_part_buf.shift
   end
   
   def next_comment_part(file)
      return @comment_part_buf.shift unless @comment_part_buf.empty?
      fill_comment_part_buf(file)
      return @comment_part_buf.shift  # may be nil, indicates eof
   end

   # Fill the comment-part buffer with at least one more CommentPart. If the language of the source
   # file is :text this is easy, just get a line. But if not, scan for comments using the delimiters
   # of the language. That gets messy.
   def fill_comment_part_buf(file)
      # if file type is :text, just grab a line and MAKE IT UNTERMINATED
      if @language == :text
         line = file.gets
         if line
            @line_no += 1
            @comment_part_buf << CommentPart.new(@line_no, line.strip, false)
         end
         return
      end

      # file type has comments, needs serious processing
      delimiters = @@comment_delimiters[@language]

      # iterate until at least one CommentPart has been produced from the file
      while @comment_part_buf.empty?
         line = file.gets
         @line_no += 1
         return if not line  # eof catching
         
         while line and line.length > 0
            # find the first location of a line-comment delimiter if present
            line_comment_pos = if delimiters[0]
                                  line.index(delimiters[0])
                               else
                                  nil
                               end
            # find the first location of a block-comment delimiter if present
            block_comment_pos = if delimiters[1]
                                   line.index(delimiters[1])
                                else
                                   nil
                                end
            # find the position of the first one (if both)
            first_comment_pos = if line_comment_pos and block_comment_pos
                                   [line_comment_pos, block_comment_pos].min
                                elsif line_comment_pos
                                   line_comment_pos
                                elsif block_comment_pos
                                   block_comment_pos
                                else
                                   nil
                                end

            if not line_comment_pos and not block_comment_pos
               # neither type of comment in this line
               # consume the line and loop back to get another one
               line = nil

            elsif first_comment_pos == line_comment_pos
               # line comment is first or only
               # the rest of the line is a terminated comment part, then consume the line
               sp = line_comment_pos + delimiters[0].length
               @comment_part_buf << CommentPart.new(@line_no, line[sp..-1].strip, true)
               line = nil

            elsif first_comment_pos == block_comment_pos
               # block comment is first or only
               # pre-trim the line to avoid problems
               sp = block_comment_pos + delimiters[1].length
               line = line[sp..-1]
               
               # look for the matching end-of-block marker
               block_comment_end = line.index(delimiters[2])
               if block_comment_end
                  # the block comment appears all on one line
                  # consume it as a terminated comment part and loop back to process rest of line
                  @comment_part_buf << CommentPart.new(@line_no, line[0...block_comment_end], true)
                  sp = block_comment_end + delimiters[2].length
                  line = line[sp..-1]

               else
                  # this line is just the beginning of the block comment
                  @comment_part_buf << CommentPart.new(@line_no, line, false)
                  
                  # continue pulling lines until a matching terminator is found or eof
                  while true
                     line = file.gets
                     @line_no += 1
                     return unless line
                     
                     block_comment_end = line.index(delimiters[2])
                     if block_comment_end
                        # just like the all-on-one-line case
                        @comment_part_buf << CommentPart.new(@line_no, line[0...block_comment_end],
                                                             true)
                        sp = block_comment_end + delimiters[2].length
                        line = line[sp..-1]
                        break
                     else
                        @comment_part_buf << CommentPart.new(@line_no, line.strip, false)
                     end
                  end
               end
               # end of block-comment handling section
            else
               # some kind of weird error
            end
         end # while line…
     end # while @comment_part_buf.empty?

   rescue Exception => ex
      puts "File associated with exception is [#{file.path}]"
      raise ex
   end


   def parse_hylite_string(string, hyliteSet)
      # first break string into name, attribute and text parts (any may be missing)
      name, atts, text = string.split(/:/)
      atts = "" if (atts == nil)
      text = "" if (text == nil)
#      puts "      split as [#{name}|#{atts}|#{text}]"

      # parse name into name attribute and retrieve (possibly contruct) matching Hylite
      nameAttributeString = name.sub(/hylite\s*([-\w]*).*/) { '_Name-' + $1 }
      if nameAttributeString == '_Name-'           # anonymous hylite is always new Hylite
         hylite = Hylite.new
         hyliteSet.hylites << hylite
      else
         nameAttribute = hyliteSet.attribTree.seek(nameAttributeString)
#         puts "here nameAttribute is #{nameAttribute.to_s}"
         if nameAttribute == nil
            nameAttribute = hyliteSet.attribTree.seekMake(nameAttributeString)
         end
#         puts "the nameAttribute is #{nameAttribute.to_s}"
#         puts "   its hyliterefs is #{nameAttribute.hyliteRefs}"

         hylite = nameAttribute.hyliteRefs[0] # because for name attribute, there's only one Hylite

         # if this is a new Hylite, create it and link it with attributeTree
         if hylite == nil

#            puts "the hylite #{nameAttributeString} is nil, so a new one is created"

            hylite = Hylite.new
            hyliteSet.hylites << hylite
            #hylite.attributes << nameAttribute
            hylite.add_attribute(nameAttribute)
            nameAttribute.hyliteRefs << hylite

#            puts "    new hyliteRefs is #{nameAttribute.hyliteRefs[0]}"

         end
      end

      # parse attribute section, seekMake and crosslink each attribute
      # Modified for 1.9: no longer “each”, now “each_line”, even though they aren't lines
      atts.strip.each_line(' ') do |attributeString|
         attribute = hyliteSet.attribTree.seekMake(attributeString.chomp(' '))
         #hylite.attributes << attribute
         hylite.add_attribute(attribute)
         attribute.hyliteRefs << hylite
      end
      
      # add text section to Hylite
      hylite.texts << text  if text.length > 0

      return hylite           # to allow further work with it, if necessary
   end
end


class WorkingSet
   attr_reader :base_dir, :see_hidden_files
   attr_writer :see_hidden_files
   
   def initialize(file)
      if not File::readable?(file)
         raise "Can't read working-set file “#{file}”"
      end

      # find @base_dir
      @base_dir = File::dirname(file)
      
      # open file, parse out all include patterns and exclude patterns
      ws_data = YAML::load(File.open(file))
      @include = ws_data['include'] || []
      @exclude = ws_data['exclude'] || []

      @see_hidden_files = false
   end

   def each_file
      flag = if @see_hidden_files then File::FNM_DOTMATCH else 0 end

      # build a set by unioning globs of each include
      files = Set.new
      @include.each {|inc| files += Dir::glob(inc, flag) }

      # prune that set by subtracting globs of each exclude
      @exclude.each {|exc| files -= Dir::glob(exc, flag) }

      # each path in the set
      #    skip if directory
      #    pull end name
      #    skip if . or ..
      #    yield it
      files.each do |path|
         next if File::directory?(path)
         fname = File::basename(path)
         next if fname == '.'
         next if fname == '..'
         next if fname =~ /.*~$/ and not @see_hidden_files
         
#         puts "visiting [#{path}]"
         yield path
      end

   end
end

class ManualSet
   attr_reader :see_hidden_files  # gonna ignore it anyway
   attr_writer :see_hidden_files
   
   def initialize(*file)
      @files = []
      file.each do |f|
         if not File::readable?(f)
            puts "Skipping unreadable file #{f}"
         else
            @files << f
         end
      end
   end

   def each_file
      @files.each do |path|
         yield path
      end
   end
end
