#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

$KCODE = 'u'

#########1#########2#########3#########4#########5#########6#########7#########8#########9########10

require 'jcode'

# hylite hylite: example: this is an example
class Hylite
   attr_reader :attributes, :texts, :locations
   attr_writer :attributes, :texts, :locations

   def initialize()
      @attributes = Array.new
      @texts = Array.new
      @locations = Array.new
   end

   def to_s
      result = String.new("hylite: ")
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


# hylite location: example-file >-using: this needs to be created by the file parser
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


# hylite attribnode: example: gosh this got complicated
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
      attribName.each('-') do |partName|
         runner = runner.downRefs[partName.chomp('-')]
         return runner if (runner == nil)
      end
      return runner
   end

   def seekMake(attribName)
      runner = self
      attribName.each('-') do |partName|
         oldRunner = runner
         runner = runner.downRefs[partName.chomp!('-')]
         if runner == nil                                   # then create an attribute node there
            runner = AttribNode.new(partName)
            runner.upRef = oldRunner
            oldRunner.downRefs[partName] = runner
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
end


class HyliteSet
   attr_reader :hylites, :attribTree
   def initialize
      @hylites = Array.new
      @attribTree = AttribNode.new("root")
   end

   def each_name
      name = @attribTree.seek('name')
      return if not name
      
      visit = lambda do |node|
#         puts "visiting #{node}"
         if node != name
            yield(node)
         end
         node.downRefs.keys.sort.each do |key|
            visit.call(node.downRefs[key])
         end
      end
      visit.call(name)
   end
end

$extension_to_type_map = {}
TYPE_TO_EXTENSION_MAP = {
   :java => ['java'],
   :c    => ['c', 'h'],
   :cpp  => ['c++', 'cpp'],
   :perl => ['pl', 'perl'],
   :ruby => ['rb', 'ruby', 'rbw'],
   :text => ['txt', 'out']
}
TYPE_TO_EXTENSION_MAP.each do |type, xs|
   xs.each{|x| $extension_to_type_map[x] = type}
end


class Scanner
   @@commentDelimiters = {:java => ['//', '/*', '*/'],
                          :c    => ['//', '/*', '*/'],
                          :cpp  => ['//', '/*', '*/'],
                          :perl => ['\x23'],               # hash character
                          :ruby => ['\x23']}               # another hash character
   
   @@embedded_delimiters = {
      '(' => ')',
      '[' => ']',
      '{' => '}',
      '<' => '>'
   }

   @@punt_mode = true

   def initialize(file)
      @file = file
      @inComment = false
      @commentState = :notComment
   end
   
   def findAllHylites(result)
#      result = HyliteSet.new
      
      #determine file type
      language = determine_type()
      
      if @@punt_mode
         File.new(@file, 'r').each_with_index do |line, ix|
            hystr = line_hylite(line)
            if hystr
               hy = parseHyliteString(hystr, result)
               hy.locations << Location.new(@file, ix)
            end
         end
      else
         #determine comment-selector for file type
         File.new(@file, 'r') do |file|
            hystr = nextHylite(file, language)
            parseHyliteString(hystr, result)
         end
      end
   end
   
   def determine_type()
      # get extension to file
      if /.*\.(.?)/ =~ @file
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
      else
         nil
      end
   end

   # use language-specific subclass for implementation of nextHylite, which looks for
   # comments, strings, and the magic phrase 'hylite' (and end delimiters) to return
   # the next hylite string, which may then be parsed
   #    what about location?

   def nextHylite(file, language)
      r_e_d = ''  # right embedded delimiter
      
      # figure out how to do this
      # while file not empty
      #    scan over file to one of:
      #       !inComment, left comment delimiter: inComment, set right comment delimiter
      #       inComment, right c.d.: !inComment
      #       inComment, "hylite": text up to right embed del. or right com. del. to buf.
      #       end of file: done
      #    parse hylite string
      
   end
   
   def parseHyliteString(string, hyliteSet)
      # first break string into name, attribute and text parts (any may be missing)
      name, atts, text = string.split(/:/)
      atts = "" if (atts == nil)
      text = "" if (text == nil)
      
      # parse name into name attribute and retrieve (possibly contruct) matching Hylite
      nameAttributeString = name.sub(/hylite\s*([-\w]*).*/) { 'name-' + $1 }
      if nameAttributeString == 'name-'           # anonymous hylite is always new Hylite
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
            hylite.attributes << nameAttribute
            nameAttribute.hyliteRefs << hylite

#            puts "    new hyliteRefs is #{nameAttribute.hyliteRefs[0]}"

         end
      end
      
      # parse attribute section, seekMake and crosslink each attribute
      atts.strip.each(' ') do |attributeString|
         attribute = hyliteSet.attribTree.seekMake(attributeString.chomp(' '))
         hylite.attributes << attribute
         attribute.hyliteRefs << hylite
      end
      
      # add text section to Hylite
      hylite.texts << text  if text.length > 0
      
      return hylite           # to allow further work with it, if necessary
   end
end

=begin
hyliteSet = HyliteSet.new

#scanner = Scanner.new("nonfile")
#hylite1 = scanner.parseHyliteString("hylite 1: one-a: some text", hyliteSet)
#puts hylite1
#hylite2 = scanner.parseHyliteString("hylite 2: two-b one-b: other text", hyliteSet)
#puts hylite2
#hylite1a = scanner.parseHyliteString("hylite 1: two-a: addendum", hyliteSet)
#puts hylite1a
#puts hylite1
#hylite3 = scanner.parseHyliteString("hylite: one-x two-x: anonymous:text", hyliteSet)
#puts hylite3

scanner = Scanner.new("testfile.txt")
scanner.findAllHylites(hyliteSet)
hyliteSet.hylites.each do |hy|
   puts hy
   hy.locations.each{|loc| puts "  " + loc.to_s}
end
=end
