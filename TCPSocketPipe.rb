#!/usr/bin/env ruby

# TCPSocketPipe.rb -- Creates I/O pipes for TCP socket tunneling.
# Copyright (C) 1999, 2000 NAKAMURA, Hiroshi

# This application is copyrighted free software by NAKAMURA, Hiroshi.
# You can redistribute it and/or modify it under the same term as Ruby.

RCS_ID = %q$Id: TCPSocketPipe.rb,v 1.9 2000/09/25 04:54:01 nakahiro Exp $

# Ruby bundled library
require 'socket'
require 'getopts'

# Extra library
#   'application.rb' by nakahiro@sarion.co.jp
#     http://www.jin.gr.jp/~nahi/Ruby/ruby.shtml#application
require 'application'
#   'dump.rb' by miche@e-mail.ne.jp
#     http://www.geocities.co.jp/SiliconValley-Oakland/2986/
require 'dump'

class TCPSocketPipe < Application
  include Log::Severity
  include Socket::Constants

  attr_accessor :dumpRequest
  attr_accessor :dumpResponse
  attr_accessor :dumpBytes
  attr_accessor :dumpBigEndian
  attr_accessor :dumpWidth

  private

  Timeout = 100			# [sec]
  ReadBlockSize = 10 * 1024	# [byte]

  class SessionPool
    public

    def each
      @pool.each do |i|
	yield i
      end
    end

    def add( serverSock, clientSock )
      @pool.push( Session.new( serverSock, clientSock ))
    end

    def del( session )
      @pool.delete_if do |i|
        session.equal?( i )
      end
    end

    private

    class Session
      attr( :server )
      attr( :client )

      private

      def initialize( server = nil, client = nil )
      	@server = server
      	@client = client
      end
    end

    def initialize
      @pool = []
    end
  end

  AppName = 'TCPSocketPipe'
  ShiftAge = 0
  ShiftSize = 0

  def initialize( srcPort, destName, destPort )
    super( AppName )
    setLog( AppName + '.log', ShiftAge, ShiftSize )
    @srcPort = srcPort.to_i
    @destName = destName
    @destPort = destPort.to_i
    @dumpRequest = true
    @dumpResponse = false
    @dumpBytes = 1
    @dumpWidth = 16
    @dumpBigEndian = false
    @sessionPool = SessionPool.new()
  end

  def run
    @waitSock = TCPServer.new( @srcPort )
    begin
      log( SEV_INFO, 'Started ... SrcPort=%s, DestName=%s, DestPort=%s' % [ @srcPort, @destName, @destPort ] )

      while true
        readWait = []
        @sessionPool.each do |session|
	  readWait.push( session.server ).push( session.client )
        end
        readWait.unshift( @waitSock )
        readReady, writeReady, except = IO.select( readWait, nil, nil, Timeout )
        next unless readReady
        readReady.each do |sock|
	  if ( @waitSock.equal?( sock ))
	    newSock = @waitSock.accept
	    log( SEV_INFO, 'Accepted ... from ' << newSock.peeraddr[2] )
	    if !addSession( newSock )
      	      log( SEV_INFO, 'Closing server socket...' )
	      newSock.close()
	    end
	  else
	    @sessionPool.each do |session|
	      transfer( session, true ) if ( sock.equal?( session.server ))
	      transfer( session, false ) if ( sock.equal?( session.client ))
	    end
	  end
	end
      end
    ensure
      @waitSock.close()
      log( SEV_INFO, 'Stopped ... SrcPort=%s, DestName=%s, DestPort=%s' % [ @srcPort, @destName, @destPort ] )
    end
  end

  def transfer( session, bServer )
    readSock = nil
    writeSock = nil
    if ( bServer )
      readSock = session.server
      writeSock = session.client
    else
      readSock = session.client
      writeSock = session.server
    end

    readBuf = ''
    begin
      readBuf << readSock.sysread( ReadBlockSize )
    rescue EOFError
      closeSession( session )
      return
    rescue Errno::ECONNRESET
      log( SEV_INFO, "#{$!} while reading." )
      closeSession( session )
      return
    rescue
      log( SEV_WARN, "Detected an exception. Stopping ... #{$!}\n" << $@.join( "\n" ))
      closeSession( session )
      return
    end

    if ( bServer )
      log( SEV_INFO, 'Transfer data ... [src] -> [dest]' )
      dumpData( readBuf ) if @dumpRequest
    else
      log( SEV_INFO, 'Transfer data ... [src] <- [dest]' )
      dumpData( readBuf ) if @dumpResponse
    end

    writeSize = 0
    while ( writeSize < readBuf.size )
      begin
      	writeSize += writeSock.syswrite( readBuf[writeSize..-1] )
      rescue Errno::ECONNRESET
      	log( SEV_INFO, "#{$!} while writing." )
      	closeSession( session )
      	return
      rescue
      	log( SEV_WARN, "Detected an exception. Stopping ... #{$!}\n" <<
	  $@.join( "\n" ))
	closeSession( session )
	return
      end
    end
  end

  def dumpData( data )
    log( SEV_INFO, "Transferred data;\n" << Debug.dump( data, "x#{ @dumpBytes }", @dumpBigEndian, @dumpWidth, 0 ))
  end

  def addSession( serverSock )
    begin
      clientSock = TCPSocket.new( @destName, @destPort )
    rescue
      log( SEV_ERROR, 'Create client socket failed.' )
      return
    end
    @sessionPool.add( serverSock, clientSock )
    log( SEV_INFO, 'Connection established.' )
  end

  def closeSession( session )
    session.server.close()
    session.client.close()
    @sessionPool.del( session )
    log( SEV_INFO, 'Connection closed.' )
  end
end

def main
  getopts( 'd', 'e', 'w:', 'x:' )
  srcPort = ARGV.shift
  destName = ARGV.shift
  destPort = ARGV.shift
  usage() if ( !srcPort or !destName or !destPort )

  # Run as a daemon...
  exit! if fork
  Process.setsid
  exit! if fork
  STDIN.close
  STDOUT.close
  STDERR.close

  app = TCPSocketPipe.new( srcPort, destName, destPort )
  app.dumpResponse = true if $OPT_d
  app.dumpBigEndian = true if $OPT_e
  app.dumpWidth = $OPT_w.to_i if $OPT_w
  app.dumpBytes = $OPT_x.to_i if $OPT_x
  app.start()
end

def usage
  STDERR.print <<EOM
Usage: #{$0} srcPort destName destPort

    Creates I/O pipes for TCP socket tunneling.

    srcPort .... source port# on your machine.
    destName ... machine name of a destination(name or ip-addr).
    destPort ... destination port# of the destName.

  Dump options:
    -d ......... dumps data from destination port(not dumped by default).
    -e ......... interprets bytes as big endian.
    -x [num] ... interprets each [num] bytes.
    -w [num] ... dump [num] bytes in each line.

#{RCS_ID}
EOM
  exit 1
end

main() if ( $0 == __FILE__ )
