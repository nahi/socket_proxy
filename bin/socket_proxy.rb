#!/usr/bin/env ruby

# socket_proxy.rb -- Creates I/O pipes for TCP socket tunneling.
# Copyright (C) 1999-2001, 2003 NAKAMURA, Hiroshi

# This application is copyrighted free software by NAKAMURA, Hiroshi.
# You can redistribute it and/or modify it under the same term as Ruby.

require 'socket_proxy'
require 'getoptlong'

def main
  opts = GetoptLong.new(['--debug', '-d', GetoptLong::NO_ARGUMENT], ['--daemon', '-s', GetoptLong::NO_ARGUMENT])
  opts.each do |name, _|
    case name
    when '--debug'
      debug = true
    when '--daemon'
      daemon = true
    end
  end

  destname = ARGV.shift
  portpairs = []
  while srcport = ARGV.shift
    destport = ARGV.shift or raise ArgumentError.new("Port must be given as a pair of src and dest.")
    portpairs << [srcport, destport]
  end
  usage if portpairs.empty? or !destname

  # To run as a daemon...
  if daemon
    exit! if fork
    Process.setsid
    exit! if fork
    STDIN.close
    STDOUT.close
    STDERR.close
  end

  app = SocketProxy.new(destname, portpairs)
  app.dump_response = true if debug
  app.start
end

def usage
  STDERR.print <<EOM
Usage: #{$0} [OPTIONS] destname srcport destport [[srcport destport]...]

    Creates I/O pipes for TCP socket tunneling.

    destname ... hostname of a destination(name or ip-addr).
    srcport .... source TCP port# or UNIX domain socket name of localhost.
    destport ... destination port# of the destination host.

  OPTIONS:
    -d ......... dumps data from destination port(not dumped by default).
    -s ......... run as a daemon.
EOM
  exit 1
end

main if $0 == __FILE__
