#!/usr/bin/ruby

require File.dirname(__FILE__) + '/impl'

inst = ConcatFileImpl.register_file('concat_test', '/tmp/concat_test')
puts inst.to_s
#def add_fragment(parent, order, fragment_name, header=nil, footer=nil)
#inst.add_fragment(nil, 1000, 'world', "world\n")
#inst.add_fragment(nil, 1000, 'hello', "hello\n")

f1 = ConcatFileImpl.register_fragment('hello', 'concat_test', 1000)
f1.set("hello\n")

f2 = ConcatFileImpl.register_fragment('world', 'concat_test', 1000)
f2.set("world\n")

f2_a = ConcatFileImpl.register_fragment('world_a', 'world', 1000)
f2_a.set("world_a\n")

f_eof = ConcatFileImpl.register_fragment('eof', 'concat_test', 9000)
f_eof.set("\nEOF\n")

puts inst.dump
inst.write
